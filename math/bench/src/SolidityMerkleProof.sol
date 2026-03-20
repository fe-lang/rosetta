// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Simplified Solady-style Merkle proof verification for benchmarking.
/// Uses the same sorted-pair hashing approach as Solady's MerkleProofLib.
/// Original: https://github.com/Vectorized/solady/blob/main/src/utils/MerkleProofLib.sol
contract SolidityMerkleProof {
    function verify(
        uint256[32] calldata proof,
        uint256 proofLen,
        bytes32 root,
        bytes32 leaf
    ) external pure returns (bool) {
        return computeRoot(proof, proofLen, leaf) == root;
    }

    function computeRoot(
        uint256[32] calldata proof,
        uint256 proofLen,
        bytes32 leaf
    ) public pure returns (bytes32 hash) {
        hash = leaf;
        assembly {
            // Fixed array: first element at calldata offset 4 (selector)
            let offset := 4
            let end := add(offset, shl(5, proofLen))

            for {} lt(offset, end) { offset := add(offset, 0x20) } {
                let sibling := calldataload(offset)
                mstore(0x00, hash)
                mstore(0x20, sibling)
                if gt(hash, sibling) {
                    mstore(0x00, sibling)
                    mstore(0x20, hash)
                }
                hash := keccak256(0x00, 0x40)
            }
        }
    }
}
