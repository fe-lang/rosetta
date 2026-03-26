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

    // SP1 v6 test vectors — 5 public inputs
    uint256 internal constant PI0 = 0x004a55ed3c7a07d0233a027278a8b7ff8681ffbd5d1ec4795c18966f6e693090;
    uint256 internal constant PI1 = 0x0f1cb7decf31e49c7934c3740bec5df3ead27bc947af739782930df6e37e9d90;
    uint256 internal constant PI2 = 0;
    uint256 internal constant PI3 = 0x008cd56e10c2fe24795cff1e1d1f40d3a324528d315674da45d26afb376e8670;
    uint256 internal constant PI4 = 0;

    // Raw gnark proof laid out for parse_proof() calldata offsets.
    // 27 words (864 bytes), ordered: lro(6), h(6), claimed_values(5), z(2),
    // z_shifted_value(1), batched_h(2), z_shifted_h(2), claimed_values[5](1),
    // bsb22_commitments(2).
    bytes internal constant RAW_PROOF = hex"06232459bd070942b95a2fd99cf8872eeee49ba7cd7ebe07ec3ef1b4b2a74d91"
        hex"154e14823bfcf0b1fcd5a43df161341594c070ae4d2814a818c262a435b68188"
        hex"15404bf08191a8b3095519798cf76c536f65e264997b59e7f9f554d7b9d24b12"
        hex"0887cd80d76b8b56c9261983cae540bfbc77f2aabb5ee16cee0362dfe079bd12"
        hex"0940fd1df4048a50b264164a972fc28739dc1365e3dcd3f0fb39a89e5dbf48e2"
        hex"2903f07b564d791699df704aeb7fc3a0d196e392eaba115b629a562d7b54daa9"
        hex"2f7c08eac11c4a53dff5104825a743418815599bec73b5b516c4a912343ad33a"
        hex"1ba1c600ce5d285d97428833bd6050d5708efc922b15ce7778d675071d5e2c0f"
        hex"0aef2040bd5a16bf81e154b76387192a91362b431311434801774584c4cca5af"
        hex"2f82a5996ddafb7b5bc009ee1c336412a1abcb9de944ec961d65de0f07c36178"
        hex"26dd3d2fab429286a3832f221505ac56cdbdc2dff07337a970b6d45aa542b395"
        hex"2fd4c0d4b57b853c080939eebac4298a3d1dbd19fa28fc2026efd88935bef01f"
        hex"0dfb52cd65b1dde09dd5e7373a63c51e05a58495258a04b6e574e340dfd536df"
        hex"27a4f599643d644fbe36b006881701451d989915930150bad493a796fb3e68e7"
        hex"0e9a1f5b75bd42b04f14a2d95d9d66cde2c75c4690ba0f617d00e726074ed370"
        hex"057402391198471c1ec7eef224209b8c50db0dde2bfd87e5aa5aac96524ae22b"
        hex"20154e58f8b39569abed5efd79c54b737ca3326b6275d67c7993a401cd1a1d5e"
        hex"1b8cf196023c29725a2b372fcb7b02579480e58281ddba98dc4d054620dd1c50"
        hex"2cb66a9d6e2f0c5dc50e32510c756b0ad319202f34171e69820014d705c3bcea"
        hex"1c72da9b1cce1cf13f273ece3ac7a7ba065d2497132355a2611dc214f8be8417"
        hex"0e547a658a424c1413881c8f2e0e29fd52bf6acf111b5074de77b5d2d784b21e"
        hex"2d52532d1394a596a5348281176f0626cb778144643fcd86064e3a2a194d1d64"
        hex"24ca8db14a80f97c3303dfba7f3aabe723fe6b6916310ea271b0ee9ad8866962"
        hex"0d99ebe9951836d7a8d672312a87b0b080b9c7d6fb4c952968e3601cbd2d0d60"
        hex"193c344ac7c5c37ac8a0f811ab22817de35f53c4b798b3ee8cb45a172919428a"
        hex"296197d04b2d5f020a80db0ee9b7a0d62f0c0576997960bf24b718a65edd5bd2"
        hex"089afd886e912bef248a89f57e075f5737fe71f57be70fdabb6a55f25f1c092b";

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
        cmd[6] = "..";
        vm.ffi(cmd);

        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash";
        readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../out/PlonkBench.bin";
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

    /// @notice End-to-end SP1 v6 Plonk proof verification through the Fe verifier.
    function test_plonkVerify() public {
        vm.pauseGasMetering();

        // selector(4) + 6 words (pi0..pi4 + proof_offset) = 4 + 192 = 196 = 0xc4
        // proof starts at calldata offset 0xc4
        uint256 proofOffset = 0xc4;

        bytes memory callData = abi.encodePacked(
            bytes4(keccak256("verifyPlonkProof(uint256,uint256,uint256,uint256,uint256,uint256)")),
            PI0, PI1, PI2, PI3, PI4,
            proofOffset,
            RAW_PROOF
        );

        vm.resumeGasMetering();

        (bool success, bytes memory result) = feAddr.call(callData);
        require(success, "call reverted");
        require(result.length >= 32, "no return data");
        bool verified = abi.decode(result, (bool));
        require(verified, "Plonk proof did NOT verify");
    }

    /// @notice Gas benchmark for Plonk verification.
    function test_plonkVerifyGas() public view {
        uint256 proofOffset = 0xc4;

        bytes memory callData = abi.encodePacked(
            bytes4(keccak256("verifyPlonkProof(uint256,uint256,uint256,uint256,uint256,uint256)")),
            PI0, PI1, PI2, PI3, PI4,
            proofOffset,
            RAW_PROOF
        );

        (bool success, bytes memory result) = feAddr.staticcall(callData);
        require(success, "call reverted");
        require(result.length >= 32, "no return data");
        bool verified = abi.decode(result, (bool));
        require(verified, "Plonk proof did NOT verify");
    }
}
