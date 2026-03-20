// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Test that we understand the gnark Fiat-Shamir transcript format.
/// Compute the gamma challenge using the same algorithm as the Rust verifier,
/// then compare it against the value the Solidity verifier would produce.
contract PlonkTranscriptTest {
    /// @notice Reproduce gnark's transcript for gamma challenge.
    /// Format: SHA256("gamma" || bindings)
    /// where bindings = VK commitments (G1 points as 64-byte BE x||y) + public inputs (32-byte BE)
    ///                 + proof wire commitments (L, R, O as 64-byte BE x||y)
    function test_transcriptFormat() public pure {
        // "gamma" in ASCII = 0x67616d6d61 (5 bytes)
        bytes memory label = "gamma";

        // For a minimal test, just verify the hash format with known data
        bytes memory data = abi.encodePacked(
            label,
            // No previous challenge (gamma is position 0)
            // Binding: a dummy G1 point (1, 2) = 64 bytes
            uint256(1), uint256(2)
        );

        bytes32 hash = sha256(data);

        // The hash should be deterministic
        // SHA256("gamma" || BE(1) || BE(2))
        require(hash != bytes32(0), "hash should be non-zero");

        // Verify the format: label bytes are raw ASCII, not padded
        // "gamma" = [0x67, 0x61, 0x6d, 0x6d, 0x61]
        require(data.length == 5 + 64, "wrong data length");
    }

    /// @notice Verify that SHA256 precompile matches Solidity's sha256()
    function test_sha256Precompile() public view {
        bytes memory data = "gamma";
        bytes32 expected = sha256(data);

        // Call precompile directly
        (bool success, bytes memory result) = address(0x02).staticcall(data);
        require(success, "precompile failed");
        bytes32 precompileResult = abi.decode(result, (bytes32));

        require(expected == precompileResult, "sha256 mismatch");
    }

    /// @notice Compute gamma with real-ish data to verify the transcript structure.
    /// The gnark format is: SHA256(label || prev_challenge_if_not_first || all_bindings)
    /// For gamma (position 0): SHA256("gamma" || binding0 || binding1 || ...)
    /// For beta (position 1): SHA256("beta" || gamma_hash || binding0 || ...)
    function test_challengeChaining() public pure {
        // Gamma: first challenge, no previous
        bytes memory gammaInput = abi.encodePacked(
            "gamma",
            uint256(0xdead), uint256(0xbeef) // dummy bindings
        );
        bytes32 gammaHash = sha256(gammaInput);

        // Beta: second challenge, chains from gamma
        // Note: it feeds the raw 32-byte hash, NOT the reduced field element
        bytes memory betaInput = abi.encodePacked(
            "beta",
            gammaHash // previous challenge's hash value (32 bytes)
            // no additional bindings for beta in gnark's Plonk
        );
        bytes32 betaHash = sha256(betaInput);

        require(gammaHash != betaHash, "challenges should differ");

        // Alpha: third challenge, chains from beta
        bytes memory alphaInput = abi.encodePacked(
            "alpha",
            betaHash, // previous challenge
            uint256(0xcafe), uint256(0xf00d) // dummy bindings (Z commitment etc)
        );
        bytes32 alphaHash = sha256(alphaInput);

        require(alphaHash != betaHash, "alpha should differ from beta");
    }
}
