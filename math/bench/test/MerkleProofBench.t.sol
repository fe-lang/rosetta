// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SolidityMerkleProof} from "../src/SolidityMerkleProof.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

interface IFeMerkleProof {
    function verify(uint256[32] calldata proof, uint256 proofLen, uint256 root, uint256 leaf) external pure returns (bool);
    function computeRoot(uint256[32] calldata proof, uint256 proofLen, uint256 leaf) external pure returns (uint256);
}

contract MerkleProofBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeMerkleProof private fe;
    SolidityMerkleProof private sol;

    // Pre-computed test tree: depth 3
    // Leaves: 0x01, 0x02, 0x03, 0x04
    // L01 = keccak(01, 02), L23 = keccak(03, 04)
    // root = keccak(L01, L23)

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
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/MerkleProofBench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr != address(0), "Fe deploy failed");
        fe = IFeMerkleProof(feAddr);

        sol = new SolidityMerkleProof();
        vm.resumeGasMetering();
    }

    // Helper: build a simple proof
    function _emptyProof() internal pure returns (uint256[32] memory proof) {}

    function _singleProof(uint256 sibling) internal pure returns (uint256[32] memory proof) {
        proof[0] = sibling;
    }

    function _sortedHash(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a < b) return uint256(keccak256(abi.encodePacked(a, b)));
        return uint256(keccak256(abi.encodePacked(b, a)));
    }

    // --- Equivalence fuzz ---

    function testFuzz_computeRoot_eq_depth1(uint256 leaf, uint256 sibling) public view {
        uint256[32] memory proof;
        proof[0] = sibling;
        uint256 feRoot = fe.computeRoot(proof, 1, leaf);
        bytes32 solRoot = sol.computeRoot(proof, 1, bytes32(leaf));
        require(feRoot == uint256(solRoot), "depth1 mismatch");
    }

    function testFuzz_computeRoot_eq_depth3(
        uint256 leaf,
        uint256 s0,
        uint256 s1,
        uint256 s2
    ) public view {
        uint256[32] memory proof;
        proof[0] = s0;
        proof[1] = s1;
        proof[2] = s2;
        uint256 feRoot = fe.computeRoot(proof, 3, leaf);
        bytes32 solRoot = sol.computeRoot(proof, 3, bytes32(leaf));
        require(feRoot == uint256(solRoot), "depth3 mismatch");
    }

    function testFuzz_verify_eq_depth3(
        uint256 leaf,
        uint256 s0,
        uint256 s1,
        uint256 s2
    ) public view {
        uint256[32] memory proof;
        proof[0] = s0;
        proof[1] = s1;
        proof[2] = s2;
        uint256 feRoot = fe.computeRoot(proof, 3, leaf);
        // Should verify
        require(fe.verify(proof, 3, feRoot, leaf), "fe verify true");
        require(sol.verify(proof, 3, bytes32(feRoot), bytes32(leaf)), "sol verify true");
        // Should not verify with wrong root
        require(!fe.verify(proof, 3, feRoot ^ 1, leaf), "fe verify false");
        require(!sol.verify(proof, 3, bytes32(feRoot ^ 1), bytes32(leaf)), "sol verify false");
    }

    // --- Gas benchmarks ---

    function _benchProof() internal pure returns (uint256[32] memory proof, uint256 leaf) {
        leaf = 0xdeadbeef;
        proof[0] = 0x1111;
        proof[1] = 0x2222;
        proof[2] = 0x3333;
        proof[3] = 0x4444;
        proof[4] = 0x5555;
        proof[5] = 0x6666;
        proof[6] = 0x7777;
    }

    function testGas_sol_computeRoot_depth7() public view {
        (uint256[32] memory proof, uint256 leaf) = _benchProof();
        sol.computeRoot(proof, 7, bytes32(leaf));
    }

    function testGas_fe_computeRoot_depth7() public view {
        (uint256[32] memory proof, uint256 leaf) = _benchProof();
        fe.computeRoot(proof, 7, leaf);
    }

    function testGas_sol_verify_depth7() public view {
        (uint256[32] memory proof, uint256 leaf) = _benchProof();
        bytes32 root = sol.computeRoot(proof, 7, bytes32(leaf));
        sol.verify(proof, 7, root, bytes32(leaf));
    }

    function testGas_fe_verify_depth7() public view {
        (uint256[32] memory proof, uint256 leaf) = _benchProof();
        uint256 root = fe.computeRoot(proof, 7, leaf);
        fe.verify(proof, 7, root, leaf);
    }

    // --- Deterministic ---

    function test_computeRoot_depth0() public view {
        uint256[32] memory proof;
        uint256 leaf = 0x42;
        require(fe.computeRoot(proof, 0, leaf) == leaf, "depth0: leaf is root");
    }

    function test_verify_roundtrip() public view {
        uint256[32] memory proof;
        proof[0] = 0xaabb;
        uint256 leaf = 0x1234;
        uint256 root = fe.computeRoot(proof, 1, leaf);
        require(fe.verify(proof, 1, root, leaf), "roundtrip");
        require(!fe.verify(proof, 1, root ^ 1, leaf), "wrong root");
    }
}
