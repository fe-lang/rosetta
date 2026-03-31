// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../sol/Escrow.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function prank(address) external;
    function deal(address, uint256) external;
    function pauseGasMetering() external;
    function resumeGasMetering() external;
}

contract EscrowBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    // Solidity contracts (for gas benchmarks)
    Escrow private sol;
    Arbiter private solArbiter;

    // Fe contract addresses (for gas benchmarks)
    address private feEscrow;
    address private feArbiter;

    // Cached Fe bytecode for deploying fresh instances in fuzz tests
    bytes private feEscrowInitcode;
    bytes private feArbiterInitcode;

    // Roles
    address constant DEPOSITOR   = address(0xD1);
    address constant BENEFICIARY = address(0xBE);

    bytes4 constant SEL_DEPOSIT    = bytes4(keccak256("deposit()"));
    bytes4 constant SEL_RELEASE    = bytes4(keccak256("release()"));
    bytes4 constant SEL_GETBALANCE = bytes4(keccak256("getBalance()"));
    bytes4 constant SEL_DORELEASE  = bytes4(keccak256("doRelease(address)"));

    function setUp() public {
        vm.pauseGasMetering();

        // --- Build Fe contracts ---
        string[] memory buildCmd = new string[](5);
        buildCmd[0] = "fe";
        buildCmd[1] = "build";
        buildCmd[2] = "--backend";
        buildCmd[3] = "sonatina";
        buildCmd[4] = "fe";
        vm.ffi(buildCmd);

        // --- Read Fe bytecode (cached for reuse in fuzz tests) ---
        {
            string[] memory readCmd = new string[](3);
            readCmd[0] = "bash";
            readCmd[1] = "-c";
            readCmd[2] = "printf '0x'; tr -d '\\n' < fe/out/Arbiter.bin";
            feArbiterInitcode = vm.ffi(readCmd);
        }
        {
            string[] memory readCmd = new string[](3);
            readCmd[0] = "bash";
            readCmd[1] = "-c";
            readCmd[2] = "printf '0x'; tr -d '\\n' < fe/out/Escrow.bin";
            feEscrowInitcode = vm.ffi(readCmd);
        }

        // --- Deploy Fe Arbiter (no constructor args) ---
        {
            bytes memory code = feArbiterInitcode;
            address _feArb;
            assembly { _feArb := create(0, add(code, 0x20), mload(code)) }
            require(_feArb != address(0), "Fe Arbiter deploy failed");
            feArbiter = _feArb;
        }

        // --- Deploy Fe Escrow (constructor args: beneficiary, arbiter) ---
        {
            bytes memory initWithArgs = abi.encodePacked(
                feEscrowInitcode,
                abi.encode(BENEFICIARY, feArbiter)
            );
            address _feEsc;
            vm.prank(DEPOSITOR);
            assembly { _feEsc := create(0, add(initWithArgs, 0x20), mload(initWithArgs)) }
            require(_feEsc != address(0), "Fe Escrow deploy failed");
            feEscrow = _feEsc;
        }

        // --- Deploy Solidity Arbiter ---
        solArbiter = new Arbiter();

        // --- Deploy Solidity Escrow (arbiter = solArbiter address) ---
        vm.prank(DEPOSITOR);
        sol = new Escrow(BENEFICIARY, address(solArbiter));

        // Fund both the test contract and the depositor address.
        // vm.prank changes the funding source for value transfers.
        vm.deal(address(this), 100 ether);
        vm.deal(DEPOSITOR, 100 ether);

        vm.resumeGasMetering();
    }

    // ================================================================
    //  Helpers
    // ================================================================

    function _feDeposit(uint256 amount) internal {
        vm.prank(DEPOSITOR);
        (bool ok,) = feEscrow.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit failed");
    }

    function _feGetBalance() internal view returns (uint256) {
        (bool ok, bytes memory ret) = feEscrow.staticcall(abi.encodeWithSelector(SEL_GETBALANCE));
        require(ok, "fe getBalance failed");
        return abi.decode(ret, (uint256));
    }

    function _feRelease() internal returns (uint256) {
        (bool ok, bytes memory ret) = feEscrow.call(abi.encodeWithSelector(SEL_RELEASE));
        require(ok, "fe release failed");
        return abi.decode(ret, (uint256));
    }

    /// Deploy a fresh pair using cached bytecode (no FFI per call).
    function _freshPair(uint256 fundAmount)
        internal
        returns (Escrow freshSol, address freshFe, Arbiter freshSolArb, address freshFeArb)
    {
        vm.pauseGasMetering();

        // Fresh Fe Arbiter
        {
            bytes memory code = feArbiterInitcode;
            address _feArb;
            assembly { _feArb := create(0, add(code, 0x20), mload(code)) }
            require(_feArb != address(0), "fresh Fe Arbiter deploy failed");
            freshFeArb = _feArb;
        }

        // Fresh Fe Escrow
        {
            bytes memory initWithArgs = abi.encodePacked(
                feEscrowInitcode,
                abi.encode(BENEFICIARY, freshFeArb)
            );
            address _feEsc;
            vm.prank(DEPOSITOR);
            assembly { _feEsc := create(0, add(initWithArgs, 0x20), mload(initWithArgs)) }
            require(_feEsc != address(0), "fresh Fe Escrow deploy failed");
            freshFe = _feEsc;
        }

        // Fresh Solidity pair
        freshSolArb = new Arbiter();
        vm.prank(DEPOSITOR);
        freshSol = new Escrow(BENEFICIARY, address(freshSolArb));

        vm.deal(address(this), fundAmount);
        vm.deal(DEPOSITOR, fundAmount);
        vm.resumeGasMetering();
    }

    // ================================================================
    //  Gas Benchmarks
    // ================================================================

    function testGas_sol_deposit() public {
        vm.prank(DEPOSITOR);
        sol.deposit{value: 1 ether}();
    }

    function testGas_fe_deposit() public {
        _feDeposit(1 ether);
    }

    function testGas_sol_getBalance() public {
        vm.pauseGasMetering();
        vm.prank(DEPOSITOR);
        sol.deposit{value: 1 ether}();
        vm.resumeGasMetering();

        sol.getBalance();
    }

    function testGas_fe_getBalance() public {
        vm.pauseGasMetering();
        _feDeposit(1 ether);
        vm.resumeGasMetering();

        _feGetBalance();
    }

    function testGas_sol_release() public {
        vm.pauseGasMetering();
        vm.prank(DEPOSITOR);
        sol.deposit{value: 1 ether}();
        vm.resumeGasMetering();

        vm.prank(address(solArbiter));
        sol.release();
    }

    function testGas_fe_release() public {
        vm.pauseGasMetering();
        _feDeposit(1 ether);
        vm.resumeGasMetering();

        vm.prank(feArbiter);
        _feRelease();
    }

    // ================================================================
    //  Equivalence Tests
    // ================================================================

    function test_equivalence_deposit_balance() public {
        (Escrow freshSol, address freshFe,,) = _freshPair(10 ether);

        uint256 amount = 2 ether;

        // Deposit on both
        vm.prank(DEPOSITOR);
        freshSol.deposit{value: amount}();

        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit failed");

        // Compare balances
        uint256 solBal = freshSol.getBalance();
        (bool ok2, bytes memory ret) = freshFe.staticcall(abi.encodeWithSelector(SEL_GETBALANCE));
        require(ok2, "fe getBalance failed");
        uint256 feBal = abi.decode(ret, (uint256));

        require(solBal == feBal, "balance mismatch after deposit");
        require(solBal == amount, "balance != deposited amount");
    }

    function test_equivalence_release() public {
        (Escrow freshSol, address freshFe, Arbiter freshSolArb, address freshFeArb) = _freshPair(10 ether);

        uint256 amount = 3 ether;

        // Deposit on both
        vm.prank(DEPOSITOR);
        freshSol.deposit{value: amount}();
        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit");

        // Release via arbiter on both
        vm.prank(address(freshSolArb));
        uint256 solAmount = freshSol.release();

        vm.prank(freshFeArb);
        (bool ok2, bytes memory ret) = freshFe.call(abi.encodeWithSelector(SEL_RELEASE));
        require(ok2, "fe release");
        uint256 feAmount = abi.decode(ret, (uint256));

        require(solAmount == feAmount, "release return mismatch");
        require(solAmount == amount, "release != deposited");

        // Balance should be zero on both
        uint256 solBal = freshSol.getBalance();
        (bool ok3, bytes memory ret2) = freshFe.staticcall(abi.encodeWithSelector(SEL_GETBALANCE));
        require(ok3, "fe getBalance after release");
        uint256 feBal = abi.decode(ret2, (uint256));

        require(solBal == 0, "sol balance not zero");
        require(feBal == 0, "fe balance not zero");
    }

    // ================================================================
    //  Fuzz Tests
    // ================================================================

    function testFuzz_deposit_balance_eq(uint256 amount) public {
        amount = amount % 10 ether + 1;

        (Escrow freshSol, address freshFe,,) = _freshPair(amount * 2 + 1 ether);

        vm.prank(DEPOSITOR);
        freshSol.deposit{value: amount}();

        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit");

        uint256 solBal = freshSol.getBalance();
        (bool ok2, bytes memory ret) = freshFe.staticcall(abi.encodeWithSelector(SEL_GETBALANCE));
        require(ok2, "fe getBalance");
        uint256 feBal = abi.decode(ret, (uint256));

        require(solBal == feBal, "fuzz: balance mismatch");
        require(solBal == amount, "fuzz: balance != amount");
    }

    function testFuzz_release_returns_amount(uint256 amount) public {
        amount = amount % 10 ether + 1;

        (Escrow freshSol, address freshFe, Arbiter freshSolArb, address freshFeArb) = _freshPair(amount * 2 + 1 ether);

        // Deposit
        vm.prank(DEPOSITOR);
        freshSol.deposit{value: amount}();
        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit");

        // Release
        vm.prank(address(freshSolArb));
        uint256 solRet = freshSol.release();

        vm.prank(freshFeArb);
        (bool ok2, bytes memory ret) = freshFe.call(abi.encodeWithSelector(SEL_RELEASE));
        require(ok2, "fe release");
        uint256 feRet = abi.decode(ret, (uint256));

        require(solRet == feRet, "fuzz: release return mismatch");
        require(solRet == amount, "fuzz: release != amount");
    }

    function testFuzz_double_deposit_reverts(uint256 a, uint256 b) public {
        a = a % 5 ether + 1;
        b = b % 5 ether + 1;

        (Escrow freshSol, address freshFe,,) = _freshPair((a + b) * 2 + 1 ether);

        // First deposit succeeds on both
        vm.prank(DEPOSITOR);
        freshSol.deposit{value: a}();

        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: a}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe first deposit failed");

        // Second deposit reverts on Solidity
        vm.prank(DEPOSITOR);
        (bool solOk,) = address(freshSol).call{value: b}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(!solOk, "sol double deposit should revert");

        // Second deposit reverts on Fe
        vm.prank(DEPOSITOR);
        (bool feOk,) = freshFe.call{value: b}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(!feOk, "fe double deposit should revert");
    }

    // ================================================================
    //  Access Control Tests
    // ================================================================

    function test_nonArbiter_cannot_release() public {
        (Escrow freshSol, address freshFe,,) = _freshPair(10 ether);

        uint256 amount = 1 ether;
        vm.prank(DEPOSITOR);
        freshSol.deposit{value: amount}();
        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit");

        // Random address tries to release
        address rando = address(0xBAD);

        vm.prank(rando);
        (bool solOk,) = address(freshSol).call(abi.encodeWithSelector(SEL_RELEASE));
        require(!solOk, "sol should revert for non-arbiter");

        vm.prank(rando);
        (bool feOk,) = freshFe.call(abi.encodeWithSelector(SEL_RELEASE));
        require(!feOk, "fe should revert for non-arbiter");
    }

    function test_arbiter_proxy_doRelease() public {
        (Escrow freshSol, address freshFe, Arbiter freshSolArb, address freshFeArb) = _freshPair(10 ether);

        uint256 amount = 2 ether;

        // Deposit on both
        vm.prank(DEPOSITOR);
        freshSol.deposit{value: amount}();
        vm.prank(DEPOSITOR);
        (bool ok,) = freshFe.call{value: amount}(abi.encodeWithSelector(SEL_DEPOSIT));
        require(ok, "fe deposit");

        // Release via arbiter proxy (doRelease)
        uint256 solRet = freshSolArb.doRelease(address(freshSol));

        (bool ok2, bytes memory ret) = freshFeArb.call(
            abi.encodeWithSelector(SEL_DORELEASE, freshFe)
        );
        require(ok2, "fe doRelease failed");
        uint256 feRet = abi.decode(ret, (uint256));

        require(solRet == feRet, "doRelease return mismatch");
        require(solRet == amount, "doRelease != amount");

        // Verify zero balance after
        uint256 solBal = freshSol.getBalance();
        (bool ok3, bytes memory ret2) = freshFe.staticcall(abi.encodeWithSelector(SEL_GETBALANCE));
        require(ok3, "fe getBalance after doRelease");
        uint256 feBal = abi.decode(ret2, (uint256));

        require(solBal == 0, "sol balance not zero after doRelease");
        require(feBal == 0, "fe balance not zero after doRelease");
    }
}
