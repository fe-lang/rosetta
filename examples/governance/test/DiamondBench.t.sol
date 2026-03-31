// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../sol/Diamond.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function prank(address) external;
    function roll(uint256) external;
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

// Interfaces matching the facet ABIs — used for both Sol diamond (via proxy)
// and Fe contract (direct calls).
interface ITokenFacet {
    function mint(address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IGovernanceFacet {
    function initGovernance(uint256 votingPeriod, uint256 quorum) external;
    function propose(string calldata description) external returns (uint256);
    function vote(uint256 proposalId, bool support) external;
    function delegate(address to) external;
    function execute(uint256 proposalId) external returns (bool);
    function getProposal(uint256 proposalId) external view returns (
        uint256 yesVotes, uint256 noVotes, uint256 voteEnd, bool executed
    );
    function proposalCount() external view returns (uint256);
    function getDelegate(address account) external view returns (address);
    function votingPower(address account) external view returns (uint256);
}

contract DiamondBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    // Solidity Diamond (behind proxy)
    address private solDiamond;
    // Fe contract (direct)
    address private feAddr;

    // Separate instances for gas benchmarks (need clean state per test)
    address private solGas;
    address private feGas;

    address constant OWNER = address(0xAD);
    address constant ALICE = address(0xA1);
    address constant BOB   = address(0xB0);

    function setUp() public {
        vm.pauseGasMetering();

        // --- Deploy Solidity Diamond ---
        DiamondDeployer deployer = new DiamondDeployer();

        // deployer.deploy() calls diamondCut as the deployer contract, so the
        // deployer is the initial caller. We need the deployer to be the owner
        // for the diamondCut call to succeed, then transfer ownership.
        (address d,,) = deployer.deploy(address(deployer));
        // Transfer ownership from deployer to OWNER
        vm.prank(address(deployer));
        IERC173(d).transferOwnership(OWNER);
        solDiamond = d;

        // Deploy a second Sol diamond for gas tests
        (address d2,,) = deployer.deploy(address(deployer));
        vm.prank(address(deployer));
        IERC173(d2).transferOwnership(OWNER);
        solGas = d2;

        // --- Deploy Fe contract ---
        uint256 optLevel = vm.envOr("FE_SONA_OPT_LEVEL", uint256(2));
        string[] memory cmd = new string[](7);
        cmd[0] = "fe";
        cmd[1] = "build";
        cmd[2] = "--backend";
        cmd[3] = "sonatina";
        cmd[4] = "-O";
        cmd[5] = optLevel == 0 ? "0" : optLevel == 1 ? "1" : "2";
        cmd[6] = "fe";
        vm.ffi(cmd);

        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < fe/out/TokenGovernanceDiamond.bin";
        bytes memory feInitcode = vm.ffi(readCmd);

        // Constructor arg: owner address
        bytes memory initWithArgs = abi.encodePacked(feInitcode, abi.encode(OWNER));

        address _fe;
        assembly { _fe := create(0, add(initWithArgs, 0x20), mload(initWithArgs)) }
        require(_fe != address(0), "Fe deploy failed");
        feAddr = _fe;

        address _fe2;
        assembly { _fe2 := create(0, add(initWithArgs, 0x20), mload(initWithArgs)) }
        require(_fe2 != address(0), "Fe deploy 2 failed");
        feGas = _fe2;

        // --- Seed both with identical state ---
        _seedState(solDiamond);
        _seedState(feAddr);
        _seedState(solGas);
        _seedState(feGas);

        vm.resumeGasMetering();
    }

    function _seedState(address target) internal {
        // Mint tokens
        vm.prank(OWNER);
        ITokenFacet(target).mint(ALICE, 1000);
        vm.prank(OWNER);
        ITokenFacet(target).mint(BOB, 500);

        // Init governance: 100 block voting period, quorum of 200
        vm.prank(OWNER);
        IGovernanceFacet(target).initGovernance(100, 200);
    }

    // =====================================================================
    // Equivalence tests
    // =====================================================================

    function test_equivalence_balanceOf() public view {
        uint256 solBal = ITokenFacet(solDiamond).balanceOf(ALICE);
        uint256 feBal = ITokenFacet(feAddr).balanceOf(ALICE);
        require(solBal == feBal, "balanceOf mismatch");
        require(solBal == 1000, "expected 1000");
    }

    function test_equivalence_totalSupply() public view {
        uint256 solSupply = ITokenFacet(solDiamond).totalSupply();
        uint256 feSupply = ITokenFacet(feAddr).totalSupply();
        require(solSupply == feSupply, "totalSupply mismatch");
    }

    function test_equivalence_transfer() public {
        vm.prank(ALICE);
        bool solOk = ITokenFacet(solDiamond).transfer(BOB, 100);

        vm.prank(ALICE);
        bool feOk = ITokenFacet(feAddr).transfer(BOB, 100);

        require(solOk == feOk, "transfer result mismatch");

        uint256 solAlice = ITokenFacet(solDiamond).balanceOf(ALICE);
        uint256 feAlice = ITokenFacet(feAddr).balanceOf(ALICE);
        require(solAlice == feAlice, "alice balance mismatch");

        uint256 solBob = ITokenFacet(solDiamond).balanceOf(BOB);
        uint256 feBob = ITokenFacet(feAddr).balanceOf(BOB);
        require(solBob == feBob, "bob balance mismatch");
    }

    function test_equivalence_propose_and_vote() public {
        // Propose
        vm.prank(ALICE);
        uint256 solId = IGovernanceFacet(solDiamond).propose("fund treasury");
        vm.prank(ALICE);
        uint256 feId = IGovernanceFacet(feAddr).propose("fund treasury");
        require(solId == feId, "proposal id mismatch");

        // Vote
        vm.prank(ALICE);
        IGovernanceFacet(solDiamond).vote(0, true);
        vm.prank(ALICE);
        IGovernanceFacet(feAddr).vote(0, true);

        vm.prank(BOB);
        IGovernanceFacet(solDiamond).vote(0, false);
        vm.prank(BOB);
        IGovernanceFacet(feAddr).vote(0, false);

        // Compare results
        (uint256 solYes, uint256 solNo,,) = IGovernanceFacet(solDiamond).getProposal(0);
        (uint256 feYes, uint256 feNo,,) = IGovernanceFacet(feAddr).getProposal(0);
        require(solYes == feYes, "yes votes mismatch");
        require(solNo == feNo, "no votes mismatch");
    }

    function test_equivalence_delegation() public {
        vm.prank(ALICE);
        IGovernanceFacet(solDiamond).delegate(BOB);
        vm.prank(ALICE);
        IGovernanceFacet(feAddr).delegate(BOB);

        uint256 solPower = IGovernanceFacet(solDiamond).votingPower(BOB);
        uint256 fePower = IGovernanceFacet(feAddr).votingPower(BOB);
        require(solPower == fePower, "voting power mismatch");
        // bob: 500 own + 1000 delegated
        require(solPower == 1500, "expected 1500");
    }

    // =====================================================================
    // Fuzz tests
    // =====================================================================

    function testFuzz_transfer_eq(uint256 amount) public {
        // Bound to alice's balance
        amount = amount % 1001;

        vm.prank(ALICE);
        bool solOk = ITokenFacet(solDiamond).transfer(BOB, amount);
        vm.prank(ALICE);
        bool feOk = ITokenFacet(feAddr).transfer(BOB, amount);

        require(solOk == feOk, "fuzz: transfer result mismatch");

        uint256 solBal = ITokenFacet(solDiamond).balanceOf(ALICE);
        uint256 feBal = ITokenFacet(feAddr).balanceOf(ALICE);
        require(solBal == feBal, "fuzz: balance mismatch");
    }

    function testFuzz_mint_and_supply(uint256 amount) public {
        // Bound to avoid overflow
        amount = amount % 1e30;

        vm.prank(OWNER);
        ITokenFacet(solDiamond).mint(ALICE, amount);
        vm.prank(OWNER);
        ITokenFacet(feAddr).mint(ALICE, amount);

        uint256 solSupply = ITokenFacet(solDiamond).totalSupply();
        uint256 feSupply = ITokenFacet(feAddr).totalSupply();
        require(solSupply == feSupply, "fuzz: supply mismatch");
    }

    // =====================================================================
    // Gas benchmarks — the Diamond overhead is the point
    // =====================================================================

    // --- Token: mint ---

    function testGas_sol_mint() public {
        vm.prank(OWNER);
        ITokenFacet(solGas).mint(ALICE, 100);
    }

    function testGas_fe_mint() public {
        vm.prank(OWNER);
        ITokenFacet(feGas).mint(ALICE, 100);
    }

    // --- Token: transfer ---

    function testGas_sol_transfer() public {
        vm.prank(ALICE);
        ITokenFacet(solGas).transfer(BOB, 50);
    }

    function testGas_fe_transfer() public {
        vm.prank(ALICE);
        ITokenFacet(feGas).transfer(BOB, 50);
    }

    // --- Token: balanceOf (read) ---

    function testGas_sol_balanceOf() public view {
        ITokenFacet(solGas).balanceOf(ALICE);
    }

    function testGas_fe_balanceOf() public view {
        ITokenFacet(feGas).balanceOf(ALICE);
    }

    // --- Governance: propose ---

    function testGas_sol_propose() public {
        vm.prank(ALICE);
        IGovernanceFacet(solGas).propose("allocate funds");
    }

    function testGas_fe_propose() public {
        vm.prank(ALICE);
        IGovernanceFacet(feGas).propose("allocate funds");
    }

    // --- Governance: vote ---

    function testGas_sol_vote() public {
        vm.prank(ALICE);
        IGovernanceFacet(solGas).propose("test");
        vm.prank(ALICE);
        IGovernanceFacet(solGas).vote(0, true);
    }

    function testGas_fe_vote() public {
        vm.prank(ALICE);
        IGovernanceFacet(feGas).propose("test");
        vm.prank(ALICE);
        IGovernanceFacet(feGas).vote(0, true);
    }

    // --- Governance: delegate ---

    function testGas_sol_delegate() public {
        vm.prank(ALICE);
        IGovernanceFacet(solGas).delegate(BOB);
    }

    function testGas_fe_delegate() public {
        vm.prank(ALICE);
        IGovernanceFacet(feGas).delegate(BOB);
    }
}
