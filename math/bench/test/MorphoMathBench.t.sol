// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SolidityMorphoMath} from "../src/SolidityMorphoMath.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

interface IFeMorphoMath {
    function mulDivDown(uint256 x, uint256 y, uint256 d) external pure returns (uint256);
    function mulDivUp(uint256 x, uint256 y, uint256 d) external pure returns (uint256);
    function wMulDown(uint256 x, uint256 y) external pure returns (uint256);
    function wDivDown(uint256 x, uint256 y) external pure returns (uint256);
    function wDivUp(uint256 x, uint256 y) external pure returns (uint256);
    function wTaylorCompounded(uint256 x, uint256 n) external pure returns (uint256);
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) external pure returns (uint256);
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) external pure returns (uint256);
}

contract MorphoMathBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeMorphoMath private fe;
    SolidityMorphoMath private sol;

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
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/MorphoMathBench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr != address(0), "Fe deploy failed");
        fe = IFeMorphoMath(feAddr);

        sol = new SolidityMorphoMath();
        vm.resumeGasMetering();
    }

    // --- Equivalence fuzz ---

    function testFuzz_mulDivDown_eq(uint256 x, uint256 y, uint256 d) public view {
        if (d == 0) return;
        // Skip overflow: x * y must fit in u256 (Morpho uses checked arithmetic)
        if (y != 0 && x > type(uint256).max / y) return;
        require(fe.mulDivDown(x, y, d) == sol.mulDivDown(x, y, d), "mulDivDown mismatch");
    }

    function testFuzz_mulDivUp_eq(uint256 x, uint256 y, uint256 d) public view {
        if (d == 0) return;
        if (y != 0 && x > type(uint256).max / y) return;
        // Also need x*y + d - 1 to not overflow
        uint256 prod = x * y;
        if (prod > type(uint256).max - (d - 1)) return;
        require(fe.mulDivUp(x, y, d) == sol.mulDivUp(x, y, d), "mulDivUp mismatch");
    }

    function testFuzz_wMulDown_eq(uint256 x, uint256 y) public view {
        if (y != 0 && x > type(uint256).max / y) return;
        require(fe.wMulDown(x, y) == sol.wMulDown(x, y), "wMulDown mismatch");
    }

    function testFuzz_toSharesDown_eq(uint256 assets, uint256 totalAssets, uint256 totalShares) public view {
        // Bound to reasonable values to avoid overflow
        if (totalShares > 1e36 || assets > 1e36 || totalAssets > 1e36) return;
        require(
            fe.toSharesDown(assets, totalAssets, totalShares) == sol.toSharesDown(assets, totalAssets, totalShares),
            "toSharesDown mismatch"
        );
    }

    // --- Gas benchmarks ---

    function testGas_sol_mulDivDown() public view { sol.mulDivDown(100e18, 50e18, 1e18); }
    function testGas_fe_mulDivDown() public view  { fe.mulDivDown(100e18, 50e18, 1e18); }
    function testGas_sol_wMulDown() public view   { sol.wMulDown(2.5e18, 0.5e18); }
    function testGas_fe_wMulDown() public view    { fe.wMulDown(2.5e18, 0.5e18); }
    function testGas_sol_taylor() public view     { sol.wTaylorCompounded(0.05e18, 365); }
    function testGas_fe_taylor() public view      { fe.wTaylorCompounded(0.05e18, 365); }

    // --- Deterministic ---

    function test_mulDivDown_basic() public view {
        require(fe.mulDivDown(10, 20, 5) == 40, "fe 10*20/5");
        require(sol.mulDivDown(10, 20, 5) == 40, "sol 10*20/5");
    }

    function test_wMulDown_basic() public view {
        require(fe.wMulDown(2e18, 3e18) == 6e18, "fe wMul 2*3");
        require(sol.wMulDown(2e18, 3e18) == 6e18, "sol wMul 2*3");
    }

    function test_toSharesDown_basic() public view {
        // 100 assets, pool has 1000 assets and 500 shares
        // shares = 100 * (500 + 1e6) / (1000 + 1) = 100 * 1000500 / 1001
        uint256 feResult = fe.toSharesDown(100, 1000, 500);
        uint256 solResult = sol.toSharesDown(100, 1000, 500);
        require(feResult == solResult, "toSharesDown mismatch");
    }

    function test_taylor_basic() public view {
        // 5% rate compounded over 365 periods
        uint256 feResult = fe.wTaylorCompounded(0.05e18, 365);
        uint256 solResult = sol.wTaylorCompounded(0.05e18, 365);
        require(feResult == solResult, "taylor mismatch");
    }
}
