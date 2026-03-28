// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SoliditySimpleAmm} from "../sol/SoliditySimpleAmm.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

interface IFeAmm {
    function addLiquidity(uint256 amountA, uint256 amountB) external;
    function swapAForB(uint256 amountIn) external returns (uint256);
    function swapBForA(uint256 amountIn) external returns (uint256);
    function getReserveA() external view returns (uint256);
    function getReserveB() external view returns (uint256);
    function getK() external view returns (uint256);
}

contract SimpleAmmBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeAmm private fe;
    SoliditySimpleAmm private sol;

    // Separate instances for gas tests (need clean state)
    IFeAmm private feGas;
    SoliditySimpleAmm private solGas;

    function setUp() public {
        vm.pauseGasMetering();

        uint256 optLevel = vm.envOr("FE_SONA_OPT_LEVEL", uint256(2));
        string[] memory cmd = new string[](7);
        cmd[0] = "fe";
        cmd[1] = "build";
        cmd[2] = "--backend";
        cmd[3] = "sonatina";
        cmd[4] = "-O";
        cmd[5] = optLevel == 0 ? "0" : optLevel == 1 ? "1" : "2";
        cmd[6] = "../..";
        vm.ffi(cmd);

        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/SimpleAmm.bin";
        bytes memory feInitcode = vm.ffi(readCmd);

        // Deploy two Fe instances
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr != address(0), "Fe deploy 1 failed");
        fe = IFeAmm(feAddr);

        address feAddr2;
        assembly { feAddr2 := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr2 != address(0), "Fe deploy 2 failed");
        feGas = IFeAmm(feAddr2);

        // Deploy two Solidity instances
        sol = new SoliditySimpleAmm();
        solGas = new SoliditySimpleAmm();

        // Seed the equivalence-test pools
        fe.addLiquidity(1000e18, 2000e18);
        sol.addLiquidity(1000e18, 2000e18);

        // Seed the gas-test pools
        feGas.addLiquidity(1000e18, 2000e18);
        solGas.addLiquidity(1000e18, 2000e18);

        vm.resumeGasMetering();
    }

    // --- Semantic equivalence ---

    function testFuzz_swapAForB_eq(uint256 amountIn) public {
        // Bound to reasonable range to avoid overflow
        if (amountIn > 1e30) return;
        uint256 feOut = fe.swapAForB(amountIn);
        uint256 solOut = sol.swapAForB(amountIn);
        require(feOut == solOut, "swapAForB mismatch");
    }

    function test_swap_sequence_eq() public {
        // Run identical swap sequences on both pools
        uint256 feOut1 = fe.swapAForB(100e18);
        uint256 solOut1 = sol.swapAForB(100e18);
        require(feOut1 == solOut1, "swap1");

        uint256 feOut2 = fe.swapBForA(200e18);
        uint256 solOut2 = sol.swapBForA(200e18);
        require(feOut2 == solOut2, "swap2");

        uint256 feOut3 = fe.swapAForB(50e18);
        uint256 solOut3 = sol.swapAForB(50e18);
        require(feOut3 == solOut3, "swap3");

        // Reserves should match
        require(fe.getReserveA() == sol.getReserveA(), "reserveA");
        require(fe.getReserveB() == sol.getReserveB(), "reserveB");
        require(fe.getK() == sol.getK(), "K");
    }

    function test_invariant_k_never_decreases() public {
        uint256 k0 = fe.getK();
        fe.swapAForB(100e18);
        uint256 k1 = fe.getK();
        require(k1 >= k0, "K decreased after swap");
        fe.swapBForA(50e18);
        uint256 k2 = fe.getK();
        require(k2 >= k1, "K decreased after swap 2");
    }

    function test_edge_cases() public {
        // Create fresh empty pool
        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/SimpleAmm.bin";
        vm.pauseGasMetering();
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        IFeAmm empty = IFeAmm(feAddr);
        vm.resumeGasMetering();

        // Swap on empty pool returns 0
        require(empty.swapAForB(100) == 0, "empty swap");
        // Zero swap returns 0
        require(fe.swapAForB(0) == 0, "zero swap");
    }

    // --- Gas benchmarks: the real comparison ---
    // These measure a full swap including storage reads, math, and storage writes.

    function testGas_sol_addLiquidity() public {
        solGas.addLiquidity(500e18, 500e18);
    }

    function testGas_fe_addLiquidity() public {
        feGas.addLiquidity(500e18, 500e18);
    }

    function testGas_sol_swapAForB() public {
        solGas.swapAForB(100e18);
    }

    function testGas_fe_swapAForB() public {
        feGas.swapAForB(100e18);
    }

    function testGas_sol_getK() public view {
        solGas.getK();
    }

    function testGas_fe_getK() public view {
        feGas.getK();
    }
}
