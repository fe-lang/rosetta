// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SolidityBN254} from "../src/SolidityBN254.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

interface IFeBN254 {
    function ecAdd(uint256 ax, uint256 ay, uint256 bx, uint256 by) external view returns (uint256, uint256);
    function ecMul(uint256 px, uint256 py, uint256 s) external view returns (uint256, uint256);
    function negate(uint256 px, uint256 py) external pure returns (uint256, uint256);
}

contract BN254BenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeBN254 private fe;
    SolidityBN254 private sol;

    // Generator point G1
    uint256 constant G1_X = 1;
    uint256 constant G1_Y = 2;

    function setUp() public {
        vm.pauseGasMetering();

        uint256 optLevel = vm.envOr("FE_SONA_OPT_LEVEL", uint256(0));
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
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/BN254Bench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr != address(0), "Fe deploy failed");
        fe = IFeBN254(feAddr);

        sol = new SolidityBN254();
        vm.resumeGasMetering();
    }

    // --- Equivalence ---

    function test_ecAdd_eq() public view {
        // G + G = 2G
        (uint256 fex, uint256 fey) = fe.ecAdd(G1_X, G1_Y, G1_X, G1_Y);
        (uint256 sx, uint256 sy) = sol.ecAdd(G1_X, G1_Y, G1_X, G1_Y);
        require(fex == sx && fey == sy, "ecAdd mismatch");
    }

    function test_ecMul_eq() public view {
        // 2 * G
        (uint256 fex, uint256 fey) = fe.ecMul(G1_X, G1_Y, 2);
        (uint256 sx, uint256 sy) = sol.ecMul(G1_X, G1_Y, 2);
        require(fex == sx && fey == sy, "ecMul mismatch");
    }

    function test_ecAdd_ecMul_consistency() public view {
        // G + G should equal 2 * G
        (uint256 addx, uint256 addy) = fe.ecAdd(G1_X, G1_Y, G1_X, G1_Y);
        (uint256 mulx, uint256 muly) = fe.ecMul(G1_X, G1_Y, 2);
        require(addx == mulx && addy == muly, "add vs mul");
    }

    function test_negate_eq() public view {
        (uint256 fex, uint256 fey) = fe.negate(G1_X, G1_Y);
        (uint256 sx, uint256 sy) = sol.negate(G1_X, G1_Y);
        require(fex == sx && fey == sy, "negate mismatch");
    }

    function test_negate_identity() public view {
        // P + (-P) = O (point at infinity)
        (uint256 nx, uint256 ny) = fe.negate(G1_X, G1_Y);
        (uint256 rx, uint256 ry) = fe.ecAdd(G1_X, G1_Y, nx, ny);
        require(rx == 0 && ry == 0, "P + -P should be identity");
    }

    function testFuzz_negate_eq(uint256 px, uint256 py) public view {
        (uint256 fex, uint256 fey) = fe.negate(px, py);
        (uint256 sx, uint256 sy) = sol.negate(px, py);
        require(fex == sx && fey == sy, "negate fuzz mismatch");
    }

    function testFuzz_ecMul_eq(uint256 s) public view {
        // Multiply generator by random scalar
        (uint256 fex, uint256 fey) = fe.ecMul(G1_X, G1_Y, s);
        (uint256 sx, uint256 sy) = sol.ecMul(G1_X, G1_Y, s);
        require(fex == sx && fey == sy, "ecMul fuzz mismatch");
    }

    // --- Gas benchmarks ---

    function testGas_sol_ecAdd() public view { sol.ecAdd(G1_X, G1_Y, G1_X, G1_Y); }
    function testGas_fe_ecAdd() public view  { fe.ecAdd(G1_X, G1_Y, G1_X, G1_Y); }
    function testGas_sol_ecMul() public view { sol.ecMul(G1_X, G1_Y, 42); }
    function testGas_fe_ecMul() public view  { fe.ecMul(G1_X, G1_Y, 42); }
    function testGas_sol_negate() public view { sol.negate(G1_X, G1_Y); }
    function testGas_fe_negate() public view  { fe.negate(G1_X, G1_Y); }
}
