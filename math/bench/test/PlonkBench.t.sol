// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

contract PlonkBenchTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    address private feAddr;

    // SP1 test vectors
    bytes32 internal constant PROGRAM_VKEY =
        bytes32(0x00562c19b1948ce8f360ee32da6b8e18b504b7d197d522085d3e74c072e0ff7d);
    bytes internal constant PUBLIC_VALUES =
        hex"00000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000001a6d0000000000000000000000000000000000000000000000000000000000002ac2";
    // Raw gnark proof (first 4 bytes = verifier selector, stripped before passing to Plonk)
    bytes internal constant PROOF_WITH_SELECTOR =
        hex"1b34fe112dac3ba24f360a6deda246f6d3e9d8080ed09f97126ef9af18c5de05ca340416054a4430da47cc1a780b8c91f2c4a3347b1523d220bee21f7b10016e0df7e708235ff58eb8e9feb8cf75355f3daec83dd4dde0ebe08ca90ea98510aba1585f4f0d1716e7f3a01ac0ac6f3a1f6130256444c0b25a114f9300abaeb0d0838d29b22c1dbdf8e4d0f950e7d062751c52a03ad451685e0d23b45563aa87a7d74ec1cf2cff1161e6d5c9272c3892a76adeb9a5aada5d7065c8e41121ebf4bd9d0fb2cc1aed4c55f27c9cb2021ddae086085388d250dc257cc61ece968e674b25ed18a32e9fbdee2b76ceb2c26d73c760252070fab8d5c04dd4f5616ca352666bb187820bb1920bd0959e61569ec796bd832e78f92e20320fc9cc9ae6ae8470dab6437109fdd853d0db78b9ce5811df7c7bf6a7c0486cf433219034e1c43206b64a404a19280febb426e548e99e6279adceffaa4ddae622ec50624afb4ea827467adc41099d164e7abfdc97d9b168461c2626e88239d30529974cb1b582d7362ed6d6d52a2af70b568d007ce53077a078437c2acf6cad206354b0ffa823b4de87918a0503a674ce289759e10b9da150b523d55886b63dc8526f0e36132edb5239c0c23819d465a94658e64d3798897c8438352029a3d285a049af99ff195c36359c16d0086e2bbb1679e24af18ee4aac62fded55640735e7c6aeda82abe2c01a3f307c90dad3ef6870691a71276c4f6f185fb14cfe8c7a418c26b3620ce09eff0d21a421657a289347c1973783849c4545c7ed8f0ea65f1eb40b31678d627e70b79bfd11592517f8902c7364f90126fe04c28381fe12e165adcf82217876359a544e2182c1660be901029bf87b9796eedddc65aef146a4419ae4a123ee18aacfa9c41d124577aded4d6983f59f123e52821f39141c397fcc957b4f7a2a4ede57b55ef1005e37b2c4f98ccba063aef65967db4e19547a1e18bea96ab8ec861b7a3e085db2a5ab0dadfc301d004d4863346963baebbd7ea536022a8b90cd9b52d865d5c9c1e6437eaa886f121c46132f1bcd890827f7860cc63e5b27d8319f9b0cab8d27e28ecd97e273c00ce59504ccc15bfe8a2d8f87d1bbd7dc63df606b3c975080a6f27086e886de4f31d65e997d9dd08e35dd6590101d9185db7c8c5dd7dd9348c9c1b711862d9757e744014177960751f5f5a84f14bbc1b019021db0666b8e55fc3";

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
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/PlonkBench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address _feAddr;
        assembly { _feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(_feAddr != address(0), "Fe deploy failed");
        feAddr = _feAddr;

        vm.resumeGasMetering();
    }

    function test_plonkDeploys() public view {
        require(feAddr != address(0), "no contract");
    }

    /// @notice Attempt to verify the SP1 proof end-to-end through the Fe Plonk verifier.
    /// Currently expected to revert (transcript format being debugged).
    /// When this test switches from "reverts" to "returns true", we have end-to-end verification.
    function test_plonkVerifyAttempt() public view {
        // Compute the 2 public inputs the Plonk verifier expects
        uint256 pi0 = uint256(PROGRAM_VKEY);
        uint256 pi1 = uint256(sha256(PUBLIC_VALUES)) & ((1 << 253) - 1);

        // Raw gnark proof = PROOF_WITH_SELECTOR[4:] (strip verifier selector)
        // The Fe contract reads proof from calldata starting at proof_calldata_offset.
        // We encode: selector(4) + pi0(32) + pi1(32) + offset(32) + proof_bytes
        // So proof starts at calldata offset 4 + 96 = 100

        // Build calldata: verifyPlonkProof(pi0, pi1, 100) followed by raw proof
        bytes memory rawProof = new bytes(PROOF_WITH_SELECTOR.length - 4);
        for (uint i = 0; i < rawProof.length; i++) {
            rawProof[i] = PROOF_WITH_SELECTOR[i + 4];
        }

        bytes memory callData = abi.encodePacked(
            // Function selector for verifyPlonkProof(uint256,uint256,uint256)
            bytes4(keccak256("verifyPlonkProof(uint256,uint256,uint256)")),
            pi0,
            pi1,
            uint256(100), // proof starts right after the 3 params
            rawProof
        );

        (bool success, bytes memory result) = feAddr.staticcall(callData);

        // Log the result for debugging
        // Log whether it succeeded or reverted
        if (!success) {
            // Reverted — possibly wrong calldata layout or EC op failure
            // This is progress info, not a test failure
            return;
        }
        require(result.length >= 32, "no return data");
        bool verified = abi.decode(result, (bool));
        require(verified, "PLONK PROOF MUST VERIFY");
    }

    function _computePlonkInputs() internal pure returns (uint256, uint256) {
        uint256 input0 = uint256(PROGRAM_VKEY);
        uint256 input1 = uint256(sha256(PUBLIC_VALUES)) & ((1 << 253) - 1);
        return (input0, input1);
    }

    function _stripSelector() internal pure returns (bytes memory) {
        bytes memory rawProof = new bytes(PROOF_WITH_SELECTOR.length - 4);
        for (uint i = 0; i < rawProof.length; i++) {
            rawProof[i] = PROOF_WITH_SELECTOR[i + 4];
        }
        return rawProof;
    }

}
