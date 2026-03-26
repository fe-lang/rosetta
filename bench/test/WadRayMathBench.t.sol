// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SolidityWadRayMath} from "../src/SolidityWadRayMath.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

interface IFeWadRayMath {
    function wadMul(uint256 a, uint256 b) external pure returns (uint256);
    function wadDiv(uint256 a, uint256 b) external pure returns (uint256);
    function rayMul(uint256 a, uint256 b) external pure returns (uint256);
    function rayDiv(uint256 a, uint256 b) external pure returns (uint256);
    function rayToWad(uint256 a) external pure returns (uint256);
    function wadToRay(uint256 a) external pure returns (uint256);
}

contract WadRayMathBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeWadRayMath private fe;
    SolidityWadRayMath private sol;

    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;
    uint256 constant HALF_WAD = 0.5e18;
    uint256 constant HALF_RAY = 0.5e27;

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
        cmd[6] = "..";
        vm.ffi(cmd);

        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../out/WadRayMathBench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr != address(0), "Fe deploy failed");
        fe = IFeWadRayMath(feAddr);

        sol = new SolidityWadRayMath();
        vm.resumeGasMetering();
    }

    // --- Equivalence fuzz ---

    function testFuzz_wadMul_eq(uint256 a, uint256 b) public view {
        // Skip overflow cases
        if (b != 0 && a > (type(uint256).max - HALF_WAD) / b) return;
        require(fe.wadMul(a, b) == sol.wadMul(a, b), "wadMul mismatch");
    }

    function testFuzz_wadDiv_eq(uint256 a, uint256 b) public view {
        if (b == 0) return;
        if (a > (type(uint256).max - b / 2) / WAD) return;
        require(fe.wadDiv(a, b) == sol.wadDiv(a, b), "wadDiv mismatch");
    }

    function testFuzz_rayMul_eq(uint256 a, uint256 b) public view {
        if (b != 0 && a > (type(uint256).max - HALF_RAY) / b) return;
        require(fe.rayMul(a, b) == sol.rayMul(a, b), "rayMul mismatch");
    }

    function testFuzz_rayDiv_eq(uint256 a, uint256 b) public view {
        if (b == 0) return;
        if (a > (type(uint256).max - b / 2) / RAY) return;
        require(fe.rayDiv(a, b) == sol.rayDiv(a, b), "rayDiv mismatch");
    }

    function testFuzz_rayToWad_eq(uint256 a) public view {
        require(fe.rayToWad(a) == sol.rayToWad(a), "rayToWad mismatch");
    }

    function testFuzz_wadToRay_eq(uint256 a) public view {
        // Skip overflow
        if (a > type(uint256).max / 1e9) return;
        require(fe.wadToRay(a) == sol.wadToRay(a), "wadToRay mismatch");
    }

    // --- Gas benchmarks ---

    function testGas_sol_wadMul() public view { sol.wadMul(2.5e18, 0.5e18); }
    function testGas_fe_wadMul() public view  { fe.wadMul(2.5e18, 0.5e18); }
    function testGas_sol_wadDiv() public view { sol.wadDiv(10e18, 3e18); }
    function testGas_fe_wadDiv() public view  { fe.wadDiv(10e18, 3e18); }
    function testGas_sol_rayMul() public view { sol.rayMul(2.5e27, 0.5e27); }
    function testGas_fe_rayMul() public view  { fe.rayMul(2.5e27, 0.5e27); }

    // --- Deterministic ---

    function test_wadMul_basic() public view {
        require(fe.wadMul(2e18, 3e18) == 6e18, "fe 2*3");
        require(sol.wadMul(2e18, 3e18) == 6e18, "sol 2*3");
        require(fe.wadMul(0, 1e18) == 0, "fe 0*1");
    }

    function test_wadDiv_basic() public view {
        require(fe.wadDiv(6e18, 3e18) == 2e18, "fe 6/3");
        require(sol.wadDiv(6e18, 3e18) == 2e18, "sol 6/3");
    }

    function test_rayToWad_rounds() public view {
        // 1.5e9 rounds up to 2
        require(fe.rayToWad(1500000001) == 2, "fe round up");
        require(sol.rayToWad(1500000001) == 2, "sol round up");
        require(fe.rayToWad(499999999) == 0, "fe round down");
    }
}
