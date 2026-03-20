// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @dev Aave V3 WadRayMath, adapted as a contract for benchmarking.
/// Original: https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/WadRayMath.sol
contract SolidityWadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function wadMul(uint256 a, uint256 b) external pure returns (uint256 c) {
        assembly {
            if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_WAD), b))))) {
                revert(0, 0)
            }
            c := div(add(mul(a, b), HALF_WAD), WAD)
        }
    }

    function wadDiv(uint256 a, uint256 b) external pure returns (uint256 c) {
        assembly {
            if or(iszero(b), iszero(iszero(gt(a, div(sub(not(0), div(b, 2)), WAD))))) {
                revert(0, 0)
            }
            c := div(add(mul(a, WAD), div(b, 2)), b)
        }
    }

    function rayMul(uint256 a, uint256 b) external pure returns (uint256 c) {
        assembly {
            if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_RAY), b))))) {
                revert(0, 0)
            }
            c := div(add(mul(a, b), HALF_RAY), RAY)
        }
    }

    function rayDiv(uint256 a, uint256 b) external pure returns (uint256 c) {
        assembly {
            if or(iszero(b), iszero(iszero(gt(a, div(sub(not(0), div(b, 2)), RAY))))) {
                revert(0, 0)
            }
            c := div(add(mul(a, RAY), div(b, 2)), b)
        }
    }

    function rayToWad(uint256 a) external pure returns (uint256 b) {
        assembly {
            b := div(a, WAD_RAY_RATIO)
            let remainder := mod(a, WAD_RAY_RATIO)
            if iszero(lt(remainder, div(WAD_RAY_RATIO, 2))) {
                b := add(b, 1)
            }
        }
    }

    function wadToRay(uint256 a) external pure returns (uint256 b) {
        assembly {
            b := mul(a, WAD_RAY_RATIO)
            if iszero(eq(div(b, WAD_RAY_RATIO), a)) {
                revert(0, 0)
            }
        }
    }
}
