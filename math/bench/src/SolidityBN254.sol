// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev BN254 EC operations via precompiles, adapted from EigenLayer BN254.sol.
/// Original: https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/src/contracts/libraries/BN254.sol
contract SolidityBN254 {
    uint256 internal constant FP_MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    function negate(uint256 px, uint256 py) external pure returns (uint256, uint256) {
        if (px == 0 && py == 0) return (0, 0);
        return (px, FP_MODULUS - (py % FP_MODULUS));
    }

    function ecAdd(uint256 ax, uint256 ay, uint256 bx, uint256 by) external view returns (uint256 rx, uint256 ry) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, ax)
            mstore(add(ptr, 0x20), ay)
            mstore(add(ptr, 0x40), bx)
            mstore(add(ptr, 0x60), by)
            if iszero(staticcall(gas(), 0x06, ptr, 0x80, ptr, 0x40)) {
                revert(0, 0)
            }
            rx := mload(ptr)
            ry := mload(add(ptr, 0x20))
        }
    }

    function ecMul(uint256 px, uint256 py, uint256 s) external view returns (uint256 rx, uint256 ry) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, px)
            mstore(add(ptr, 0x20), py)
            mstore(add(ptr, 0x40), s)
            if iszero(staticcall(gas(), 0x07, ptr, 0x60, ptr, 0x40)) {
                revert(0, 0)
            }
            rx := mload(ptr)
            ry := mload(add(ptr, 0x20))
        }
    }
}
