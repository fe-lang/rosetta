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
    function expectRevert() external;
    function assertEq(uint256 a, uint256 b) external pure;
}

// Shared interface for token ops (same selectors on both Fe and Sol)
interface IToken {
    function mint(address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

// Governance interface for the Solidity Diamond (propose takes string)
interface IGovSol {
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

// Governance interface for the Fe contract (propose takes uint256)
interface IGovFe {
    function propose(uint256 description) external returns (uint256);
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

contract GovernanceBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    // Solidity Diamond instances
    address private solDiamond;
    address private solGas;
    // Fe contract instances
    address private feAddr;
    address private feGas;

    address constant OWNER = address(0xAD);
    address constant ALICE = address(0xA1);
    address constant BOB   = address(0xB0);

    uint256 constant VOTING_PERIOD = 100;
    uint256 constant QUORUM = 200;

    function setUp() public {
        vm.pauseGasMetering();

        // --- Deploy Solidity Diamond ---
        solDiamond = _deploySolDiamond();
        solGas = _deploySolDiamond();

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
        readCmd[2] = "printf '0x'; tr -d '\\n' < fe/out/MultiApp.bin";
        bytes memory feInitcode = vm.ffi(readCmd);

        // Fe constructor: (uint256 voting_period, uint256 quorum)
        // The deployer (this contract) becomes the owner via ctx.caller() in init
        feAddr = _deployFe(feInitcode);
        feGas = _deployFe(feInitcode);

        // Transfer Fe ownership isn't needed; the deployer IS the owner.
        // But we need OWNER to be the owner for prank-based tests.
        // Fe has no transferOwnership, so we deploy from OWNER's perspective.
        // Actually, the test contract deploys Fe, so test contract is owner.
        // We'll use address(this) as owner for Fe, and OWNER for Sol.
        // To keep things uniform, let's just have the test contract be the
        // caller for mint (no prank needed for Fe mints from test contract).
        //
        // Alternative: we make the test contract the owner of both.
        // Let's do that. The Sol diamond deployer already sets the test contract
        // as owner (we pass address(this)).

        // --- Seed both with identical state ---
        _seedState(solDiamond, true);
        _seedState(feAddr, false);
        _seedState(solGas, true);
        _seedState(feGas, false);

        vm.resumeGasMetering();
    }

    function _deploySolDiamond() internal returns (address) {
        DiamondDeployer deployer = new DiamondDeployer();
        (address d,,) = deployer.deploy(address(deployer));

        // Transfer ownership from deployer contract to this test contract
        vm.prank(address(deployer));
        IERC173(d).transferOwnership(address(this));

        // Add votingPower selector (missing from DiamondDeployer)
        bytes4[] memory extraSelectors = new bytes4[](1);
        extraSelectors[0] = GovernanceFacet.votingPower.selector;
        GovernanceFacet govFacet = new GovernanceFacet();
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(govFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: extraSelectors
        });
        IDiamondCut(d).diamondCut(cuts, address(0), "");

        return d;
    }

    function _deployFe(bytes memory feInitcode) internal returns (address) {
        bytes memory initWithArgs = abi.encodePacked(
            feInitcode,
            abi.encode(VOTING_PERIOD, QUORUM)
        );
        address _fe;
        assembly { _fe := create(0, add(initWithArgs, 0x20), mload(initWithArgs)) }
        require(_fe != address(0), "Fe deploy failed");
        return _fe;
    }

    function _seedState(address target, bool isSol) internal {
        // Mint tokens (test contract is owner of both)
        IToken(target).mint(ALICE, 1000);
        IToken(target).mint(BOB, 500);

        // Init governance on Solidity Diamond only (Fe does it in constructor)
        if (isSol) {
            IGovSol(target).initGovernance(VOTING_PERIOD, QUORUM);
        }
    }

    // =====================================================================
    // Helper: propose on Fe (uint256 description)
    // =====================================================================

    function _fePropose(address fe, address caller, uint256 desc) internal returns (uint256) {
        vm.prank(caller);
        return IGovFe(fe).propose(desc);
    }

    function _solPropose(address sol, address caller, string memory desc) internal returns (uint256) {
        vm.prank(caller);
        return IGovSol(sol).propose(desc);
    }

    // =====================================================================
    // Equivalence tests
    // =====================================================================

    function test_equivalence_balanceOf() public view {
        uint256 solBal = IToken(solDiamond).balanceOf(ALICE);
        uint256 feBal = IToken(feAddr).balanceOf(ALICE);
        require(solBal == feBal, "balanceOf mismatch");
        require(solBal == 1000, "expected 1000");
    }

    function test_equivalence_totalSupply() public view {
        uint256 solSupply = IToken(solDiamond).totalSupply();
        uint256 feSupply = IToken(feAddr).totalSupply();
        require(solSupply == feSupply, "totalSupply mismatch");
        require(solSupply == 1500, "expected 1500");
    }

    function test_equivalence_transfer() public {
        vm.prank(ALICE);
        bool solOk = IToken(solDiamond).transfer(BOB, 100);
        vm.prank(ALICE);
        bool feOk = IToken(feAddr).transfer(BOB, 100);

        require(solOk == feOk, "transfer result mismatch");
        require(
            IToken(solDiamond).balanceOf(ALICE) == IToken(feAddr).balanceOf(ALICE),
            "alice balance mismatch"
        );
        require(
            IToken(solDiamond).balanceOf(BOB) == IToken(feAddr).balanceOf(BOB),
            "bob balance mismatch"
        );
    }

    function test_equivalence_transfer_insufficient() public {
        // Transfer more than balance should return false on both
        vm.prank(ALICE);
        bool solOk = IToken(solDiamond).transfer(BOB, 9999);
        vm.prank(ALICE);
        bool feOk = IToken(feAddr).transfer(BOB, 9999);

        require(!solOk, "sol should fail");
        require(!feOk, "fe should fail");
        // Balances unchanged
        require(
            IToken(solDiamond).balanceOf(ALICE) == IToken(feAddr).balanceOf(ALICE),
            "balance mismatch after failed transfer"
        );
    }

    function test_equivalence_propose_and_vote() public {
        uint256 solId = _solPropose(solDiamond, ALICE, "fund treasury");
        uint256 feId = _fePropose(feAddr, ALICE, 42);
        require(solId == feId, "proposal id mismatch");
        require(solId == 0, "first proposal should be id 0");

        // Vote yes from ALICE, no from BOB
        vm.prank(ALICE);
        IGovSol(solDiamond).vote(0, true);
        vm.prank(ALICE);
        IGovFe(feAddr).vote(0, true);

        vm.prank(BOB);
        IGovSol(solDiamond).vote(0, false);
        vm.prank(BOB);
        IGovFe(feAddr).vote(0, false);

        // Compare vote tallies
        (uint256 solYes, uint256 solNo,,) = IGovSol(solDiamond).getProposal(0);
        (uint256 feYes, uint256 feNo,,) = IGovFe(feAddr).getProposal(0);
        require(solYes == feYes, "yes votes mismatch");
        require(solNo == feNo, "no votes mismatch");
        require(solYes == 1000, "alice should have 1000 weight");
        require(solNo == 500, "bob should have 500 weight");
    }

    function test_equivalence_delegation() public {
        vm.prank(ALICE);
        IGovSol(solDiamond).delegate(BOB);
        vm.prank(ALICE);
        IGovFe(feAddr).delegate(BOB);

        uint256 solPower = IGovSol(solDiamond).votingPower(BOB);
        uint256 fePower = IGovFe(feAddr).votingPower(BOB);
        require(solPower == fePower, "voting power mismatch");
        require(solPower == 1500, "expected 1500 (500 own + 1000 delegated)");

        // Verify delegate address stored
        address solDel = IGovSol(solDiamond).getDelegate(ALICE);
        address feDel = IGovFe(feAddr).getDelegate(ALICE);
        require(solDel == feDel, "delegate mismatch");
        require(solDel == BOB, "delegate should be BOB");
    }

    function test_equivalence_redelegate() public {
        address CAROL = address(0xC0);

        // Delegate ALICE -> BOB
        vm.prank(ALICE);
        IGovSol(solDiamond).delegate(BOB);
        vm.prank(ALICE);
        IGovFe(feAddr).delegate(BOB);

        // Redelegate ALICE -> CAROL
        vm.prank(ALICE);
        IGovSol(solDiamond).delegate(CAROL);
        vm.prank(ALICE);
        IGovFe(feAddr).delegate(CAROL);

        // BOB should lose delegated weight
        uint256 solBobPower = IGovSol(solDiamond).votingPower(BOB);
        uint256 feBobPower = IGovFe(feAddr).votingPower(BOB);
        require(solBobPower == feBobPower, "bob power mismatch after redelegate");
        require(solBobPower == 500, "bob should have only own 500");

        // CAROL should gain it
        uint256 solCarolPower = IGovSol(solDiamond).votingPower(CAROL);
        uint256 feCarolPower = IGovFe(feAddr).votingPower(CAROL);
        require(solCarolPower == feCarolPower, "carol power mismatch");
        require(solCarolPower == 1000, "carol should have 1000 delegated");
    }

    function test_equivalence_execute() public {
        // Create proposal and vote to meet quorum
        _solPropose(solDiamond, ALICE, "execute test");
        _fePropose(feAddr, ALICE, 1);

        vm.prank(ALICE);
        IGovSol(solDiamond).vote(0, true);
        vm.prank(ALICE);
        IGovFe(feAddr).vote(0, true);

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Execute - quorum is 200, ALICE voted 1000 yes, should pass
        bool solResult = IGovSol(solDiamond).execute(0);
        bool feResult = IGovFe(feAddr).execute(0);
        require(solResult == feResult, "execute result mismatch");
        require(solResult, "should pass with majority yes");

        // Verify executed flag
        (,,, bool solExec) = IGovSol(solDiamond).getProposal(0);
        (,,, bool feExec) = IGovFe(feAddr).getProposal(0);
        require(solExec && feExec, "executed flag should be true");
    }

    function test_equivalence_execute_fails_quorum() public {
        // Mint a tiny amount to a new voter so they can propose
        address TINY = address(0xDD);
        IToken(solDiamond).mint(TINY, 1);
        IToken(feAddr).mint(TINY, 1);

        _solPropose(solDiamond, TINY, "low quorum");
        _fePropose(feAddr, TINY, 2);

        // Only TINY votes (weight 1), quorum is 200
        vm.prank(TINY);
        IGovSol(solDiamond).vote(0, true);
        vm.prank(TINY);
        IGovFe(feAddr).vote(0, true);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Both should revert: quorum not met
        (bool solOk,) = solDiamond.call(
            abi.encodeWithSelector(IGovSol.execute.selector, uint256(0))
        );
        (bool feOk,) = feAddr.call(
            abi.encodeWithSelector(IGovFe.execute.selector, uint256(0))
        );
        require(!solOk && !feOk, "both should revert on quorum failure");
    }

    function test_equivalence_proposalCount() public {
        require(IGovSol(solDiamond).proposalCount() == 0, "sol count should be 0");
        require(IGovFe(feAddr).proposalCount() == 0, "fe count should be 0");

        _solPropose(solDiamond, ALICE, "one");
        _fePropose(feAddr, ALICE, 1);

        _solPropose(solDiamond, BOB, "two");
        _fePropose(feAddr, BOB, 2);

        uint256 solCount = IGovSol(solDiamond).proposalCount();
        uint256 feCount = IGovFe(feAddr).proposalCount();
        require(solCount == feCount, "proposal count mismatch");
        require(solCount == 2, "expected 2 proposals");
    }

    function test_equivalence_doubleVotePrevention() public {
        _solPropose(solDiamond, ALICE, "no doubles");
        _fePropose(feAddr, ALICE, 3);

        vm.prank(ALICE);
        IGovSol(solDiamond).vote(0, true);
        vm.prank(ALICE);
        IGovFe(feAddr).vote(0, true);

        // Second vote should revert on both
        vm.prank(ALICE);
        (bool solOk,) = solDiamond.call(
            abi.encodeWithSelector(IGovSol.vote.selector, uint256(0), true)
        );
        vm.prank(ALICE);
        (bool feOk,) = feAddr.call(
            abi.encodeWithSelector(IGovFe.vote.selector, uint256(0), true)
        );
        require(!solOk && !feOk, "both should revert on double vote");
    }

    function test_equivalence_votingPeriodEnforcement() public {
        _solPropose(solDiamond, ALICE, "period test");
        _fePropose(feAddr, ALICE, 4);

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Voting should fail after period ends
        vm.prank(ALICE);
        (bool solOk,) = solDiamond.call(
            abi.encodeWithSelector(IGovSol.vote.selector, uint256(0), true)
        );
        vm.prank(ALICE);
        (bool feOk,) = feAddr.call(
            abi.encodeWithSelector(IGovFe.vote.selector, uint256(0), true)
        );
        require(!solOk && !feOk, "both should revert after voting period");
    }

    function test_equivalence_mintOnlyOwner() public {
        // Non-owner mint should revert on both
        vm.prank(ALICE);
        (bool solOk,) = solDiamond.call(
            abi.encodeWithSelector(IToken.mint.selector, ALICE, uint256(100))
        );
        vm.prank(ALICE);
        (bool feOk,) = feAddr.call(
            abi.encodeWithSelector(IToken.mint.selector, ALICE, uint256(100))
        );
        require(!solOk && !feOk, "both should revert on non-owner mint");
    }

    function test_equivalence_delegateVoteWeight() public {
        // ALICE delegates to BOB, then BOB votes with combined weight
        vm.prank(ALICE);
        IGovSol(solDiamond).delegate(BOB);
        vm.prank(ALICE);
        IGovFe(feAddr).delegate(BOB);

        _solPropose(solDiamond, BOB, "delegated vote");
        _fePropose(feAddr, BOB, 5);

        vm.prank(BOB);
        IGovSol(solDiamond).vote(0, true);
        vm.prank(BOB);
        IGovFe(feAddr).vote(0, true);

        (uint256 solYes,,,) = IGovSol(solDiamond).getProposal(0);
        (uint256 feYes,,,) = IGovFe(feAddr).getProposal(0);
        require(solYes == feYes, "delegated vote weight mismatch");
        require(solYes == 1500, "expected 1500 (500 own + 1000 delegated)");
    }

    // =====================================================================
    // Fuzz tests
    // =====================================================================

    function testFuzz_transfer_eq(uint256 amount) public {
        // Bound to ALICE's balance (1000)
        amount = amount % 1001;

        vm.prank(ALICE);
        bool solOk = IToken(solDiamond).transfer(BOB, amount);
        vm.prank(ALICE);
        bool feOk = IToken(feAddr).transfer(BOB, amount);

        require(solOk == feOk, "fuzz: transfer result mismatch");
        require(
            IToken(solDiamond).balanceOf(ALICE) == IToken(feAddr).balanceOf(ALICE),
            "fuzz: alice balance mismatch"
        );
        require(
            IToken(solDiamond).balanceOf(BOB) == IToken(feAddr).balanceOf(BOB),
            "fuzz: bob balance mismatch"
        );
    }

    function testFuzz_vote_weight_eq(uint256 mintAmount) public {
        // Bound to reasonable range
        mintAmount = (mintAmount % 1e24) + 1; // at least 1 to allow proposing

        address VOTER = address(0xFE);

        IToken(solDiamond).mint(VOTER, mintAmount);
        IToken(feAddr).mint(VOTER, mintAmount);

        // Propose and vote
        _solPropose(solDiamond, VOTER, "fuzz vote");
        _fePropose(feAddr, VOTER, 99);

        vm.prank(VOTER);
        IGovSol(solDiamond).vote(0, true);
        vm.prank(VOTER);
        IGovFe(feAddr).vote(0, true);

        (uint256 solYes,,,) = IGovSol(solDiamond).getProposal(0);
        (uint256 feYes,,,) = IGovFe(feAddr).getProposal(0);
        require(solYes == feYes, "fuzz: vote weight mismatch");
        require(solYes == mintAmount, "fuzz: vote weight should equal minted amount");
    }

    function testFuzz_delegation_eq(uint256 amount) public {
        // Bound to reasonable range
        amount = (amount % 1e24) + 1;

        address DELEGATOR = address(0xDE);
        address DELEGATEE = address(0xEE);

        IToken(solDiamond).mint(DELEGATOR, amount);
        IToken(feAddr).mint(DELEGATOR, amount);

        vm.prank(DELEGATOR);
        IGovSol(solDiamond).delegate(DELEGATEE);
        vm.prank(DELEGATOR);
        IGovFe(feAddr).delegate(DELEGATEE);

        uint256 solPower = IGovSol(solDiamond).votingPower(DELEGATEE);
        uint256 fePower = IGovFe(feAddr).votingPower(DELEGATEE);
        require(solPower == fePower, "fuzz: delegation power mismatch");
        require(solPower == amount, "fuzz: delegated power should equal minted amount");

        // Verify delegator's own power is just their balance (no delegation to them)
        uint256 solDelegatorPower = IGovSol(solDiamond).votingPower(DELEGATOR);
        uint256 feDelegatorPower = IGovFe(feAddr).votingPower(DELEGATOR);
        require(
            solDelegatorPower == feDelegatorPower,
            "fuzz: delegator power mismatch"
        );
    }

    // =====================================================================
    // Gas benchmarks
    // =====================================================================

    // --- Token: mint ---

    function testGas_sol_mint() public {
        IToken(solGas).mint(ALICE, 100);
    }

    function testGas_fe_mint() public {
        IToken(feGas).mint(ALICE, 100);
    }

    // --- Token: transfer ---

    function testGas_sol_transfer() public {
        vm.prank(ALICE);
        IToken(solGas).transfer(BOB, 50);
    }

    function testGas_fe_transfer() public {
        vm.prank(ALICE);
        IToken(feGas).transfer(BOB, 50);
    }

    // --- Token: balanceOf ---

    function testGas_sol_balanceOf() public view {
        IToken(solGas).balanceOf(ALICE);
    }

    function testGas_fe_balanceOf() public view {
        IToken(feGas).balanceOf(ALICE);
    }

    // --- Governance: propose ---

    function testGas_sol_propose() public {
        vm.prank(ALICE);
        IGovSol(solGas).propose("allocate funds");
    }

    function testGas_fe_propose() public {
        vm.prank(ALICE);
        IGovFe(feGas).propose(42);
    }

    // --- Governance: vote ---

    function testGas_sol_vote() public {
        vm.pauseGasMetering();
        vm.prank(ALICE);
        IGovSol(solGas).propose("test");
        vm.resumeGasMetering();

        vm.prank(ALICE);
        IGovSol(solGas).vote(0, true);
    }

    function testGas_fe_vote() public {
        vm.pauseGasMetering();
        vm.prank(ALICE);
        IGovFe(feGas).propose(1);
        vm.resumeGasMetering();

        vm.prank(ALICE);
        IGovFe(feGas).vote(0, true);
    }

    // --- Governance: delegate ---

    function testGas_sol_delegate() public {
        vm.prank(ALICE);
        IGovSol(solGas).delegate(BOB);
    }

    function testGas_fe_delegate() public {
        vm.prank(ALICE);
        IGovFe(feGas).delegate(BOB);
    }

    // --- Governance: execute ---

    function testGas_sol_execute() public {
        vm.pauseGasMetering();
        vm.prank(ALICE);
        IGovSol(solGas).propose("exec test");
        vm.prank(ALICE);
        IGovSol(solGas).vote(0, true);
        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.resumeGasMetering();

        IGovSol(solGas).execute(0);
    }

    function testGas_fe_execute() public {
        vm.pauseGasMetering();
        vm.prank(ALICE);
        IGovFe(feGas).propose(1);
        vm.prank(ALICE);
        IGovFe(feGas).vote(0, true);
        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.resumeGasMetering();

        IGovFe(feGas).execute(0);
    }
}
