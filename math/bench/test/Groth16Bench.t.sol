// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

interface IFeGroth16 {
    function verifyProof(uint256 input) external view returns (bool);
}

contract Groth16BenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IFeGroth16 private fe;

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
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/Groth16Bench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address feAddr;
        assembly { feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(feAddr != address(0), "Fe deploy failed");
        fe = IFeGroth16(feAddr);

        vm.resumeGasMetering();
    }

    /// @notice Verify proof that 33 = 3 × 11 (the public input is 33 = 0x21).
    /// This is the real Groth16 verification — ecMul, ecAdd, ecPairing precompiles.
    function test_verifyValidProof() public view {
        bool result = fe.verifyProof(0x21);
        require(result, "Valid proof should verify");
    }

    /// @notice Invalid input should fail verification.
    function test_verifyInvalidInput() public view {
        bool result = fe.verifyProof(0x22);  // 34 is not 33
        require(!result, "Invalid input should not verify");
    }

    /// @notice Zero input should not verify (0 is not the product).
    function test_verifyZeroInput() public view {
        bool result = fe.verifyProof(0x00);
        require(!result, "Zero input should not verify");
    }

    /// @notice Gas benchmark for Groth16 verification.
    function testGas_fe_groth16Verify() public view {
        fe.verifyProof(0x21);
    }
}
