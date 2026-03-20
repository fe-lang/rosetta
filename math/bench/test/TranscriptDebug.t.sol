// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

/// @dev Call the Fe PlonkBench contract's debug endpoints for each challenge
/// and compare against values computed by the actual SP1 Solidity verifier.
contract TranscriptDebugTest {
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);
    address private feAddr;

    bytes32 constant VKEY = bytes32(0x00562c19b1948ce8f360ee32da6b8e18b504b7d197d522085d3e74c072e0ff7d);
    bytes constant PUB_VALUES = hex"00000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000001a6d0000000000000000000000000000000000000000000000000000000000002ac2";
    bytes constant PROOF = hex"1b34fe112dac3ba24f360a6deda246f6d3e9d8080ed09f97126ef9af18c5de05ca340416054a4430da47cc1a780b8c91f2c4a3347b1523d220bee21f7b10016e0df7e708235ff58eb8e9feb8cf75355f3daec83dd4dde0ebe08ca90ea98510aba1585f4f0d1716e7f3a01ac0ac6f3a1f6130256444c0b25a114f9300abaeb0d0838d29b22c1dbdf8e4d0f950e7d062751c52a03ad451685e0d23b45563aa87a7d74ec1cf2cff1161e6d5c9272c3892a76adeb9a5aada5d7065c8e41121ebf4bd9d0fb2cc1aed4c55f27c9cb2021ddae086085388d250dc257cc61ece968e674b25ed18a32e9fbdee2b76ceb2c26d73c760252070fab8d5c04dd4f5616ca352666bb187820bb1920bd0959e61569ec796bd832e78f92e20320fc9cc9ae6ae8470dab6437109fdd853d0db78b9ce5811df7c7bf6a7c0486cf433219034e1c43206b64a404a19280febb426e548e99e6279adceffaa4ddae622ec50624afb4ea827467adc41099d164e7abfdc97d9b168461c2626e88239d30529974cb1b582d7362ed6d6d52a2af70b568d007ce53077a078437c2acf6cad206354b0ffa823b4de87918a0503a674ce289759e10b9da150b523d55886b63dc8526f0e36132edb5239c0c23819d465a94658e64d3798897c8438352029a3d285a049af99ff195c36359c16d0086e2bbb1679e24af18ee4aac62fded55640735e7c6aeda82abe2c01a3f307c90dad3ef6870691a71276c4f6f185fb14cfe8c7a418c26b3620ce09eff0d21a421657a289347c1973783849c4545c7ed8f0ea65f1eb40b31678d627e70b79bfd11592517f8902c7364f90126fe04c28381fe12e165adcf82217876359a544e2182c1660be901029bf87b9796eedddc65aef146a4419ae4a123ee18aacfa9c41d124577aded4d6983f59f123e52821f39141c397fcc957b4f7a2a4ede57b55ef1005e37b2c4f98ccba063aef65967db4e19547a1e18bea96ab8ec861b7a3e085db2a5ab0dadfc301d004d4863346963baebbd7ea536022a8b90cd9b52d865d5c9c1e6437eaa886f121c46132f1bcd890827f7860cc63e5b27d8319f9b0cab8d27e28ecd97e273c00ce59504ccc15bfe8a2d8f87d1bbd7dc63df606b3c975080a6f27086e886de4f31d65e997d9dd08e35dd6590101d9185db7c8c5dd7dd9348c9c1b711862d9757e744014177960751f5f5a84f14bbc1b019021db0666b8e55fc3";

    function setUp() public {
        vm.pauseGasMetering();
        uint256 optLevel = vm.envOr("FE_SONA_OPT_LEVEL", uint256(0));
        string[] memory cmd = new string[](7);
        cmd[0] = "fe"; cmd[1] = "build"; cmd[2] = "--backend"; cmd[3] = "sonatina";
        cmd[4] = "-O"; cmd[5] = optLevel == 0 ? "0" : optLevel == 1 ? "1" : "2"; cmd[6] = "../..";
        vm.ffi(cmd);
        string[] memory readCmd = new string[](3);
        readCmd[0] = "bash"; readCmd[1] = "-c";
        readCmd[2] = "printf '0x'; tr -d '\\n' < ../../out/PlonkBench.bin";
        bytes memory feInitcode = vm.ffi(readCmd);
        address _feAddr;
        assembly { _feAddr := create(0, add(feInitcode, 0x20), mload(feInitcode)) }
        require(_feAddr != address(0), "deploy failed");
        feAddr = _feAddr;
        vm.resumeGasMetering();
    }

    function _callDebug(string memory sig) internal view returns (uint256) {
        uint256 pi0 = uint256(VKEY);
        uint256 pi1 = uint256(sha256(PUB_VALUES)) & ((1 << 253) - 1);

        // Strip 4-byte selector prefix
        bytes memory rawProof = new bytes(PROOF.length - 4);
        for (uint i = 0; i < rawProof.length; i++) rawProof[i] = PROOF[i + 4];

        bytes memory callData = abi.encodePacked(
            bytes4(keccak256(bytes(sig))),
            pi0, pi1, uint256(100),
            rawProof
        );

        (bool success, bytes memory result) = feAddr.staticcall(callData);
        require(success, string(abi.encodePacked(sig, " reverted")));
        return abi.decode(result, (uint256));
    }

    function test_feGamma() public view {
        uint256 gamma = _callDebug("debugGamma(uint256,uint256,uint256)");
        // Expected from our previous verified test
        require(gamma == 0xff308047da30967bfb048fd879ebf74334296494aef3df387308863b238540ac, "gamma wrong");
    }

    function test_feBeta() public view {
        uint256 beta = _callDebug("debugBeta(uint256,uint256,uint256)");
        require(beta == 0xfeb7b77d7a9eea8fa534812c812122688d9bfae56068c10501871e0844bf6080, "beta wrong");
    }

    function test_feAlpha() public view {
        uint256 alpha = _callDebug("debugAlpha(uint256,uint256,uint256)");
        require(alpha == 0xff4c7467b40d51a6f526d845720e5945d4f0620f8ebc56ea9900f8c84ba6048f, "alpha wrong");
    }

    function test_feZeta() public view {
        uint256 zeta = _callDebug("debugZeta(uint256,uint256,uint256)");
        require(zeta == 0xc3b84ae752216a5cae098493e1282230f2d8db540b958f2c6d0067f9ee0fed8a, "zeta wrong");
    }

    function test_fePI() public view {
        uint256 pi0 = uint256(VKEY);
        uint256 pi1 = uint256(sha256(PUB_VALUES)) & ((1 << 253) - 1);
        bytes memory rawProof = new bytes(PROOF.length - 4);
        for (uint i = 0; i < rawProof.length; i++) rawProof[i] = PROOF[i + 4];

        bytes memory callData = abi.encodePacked(
            bytes4(keccak256("debugPI(uint256,uint256,uint256)")),
            pi0, pi1, uint256(100),
            rawProof
        );
        (bool success, bytes memory result) = feAddr.staticcall(callData);
        require(success, "debugPI reverted");
        (uint256 piTotal, uint256 hashFr) = abi.decode(result, (uint256, uint256));

        // Expected hash_fr from Python computation
        require(hashFr == 0x11fde042bd38090174940ef4ce967657b9b334a8f80c25694311c8846320a582, "hash_fr wrong");
        // Expected PI total from Python computation
        require(piTotal == 0x20fcd3e30d1d7c58a1401c04a2e4e114a614a5f0dbe1dbbcc8a84bc28058fef6, "PI wrong");
    }
}
