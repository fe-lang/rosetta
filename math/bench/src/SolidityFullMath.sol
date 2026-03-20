// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Uniswap V3 FullMath.sol adapted for Solidity 0.8+ (unchecked blocks).
/// Original: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol
/// Credit: Remco Bloemen (https://xn--2-umb.com/21/muldiv)
contract SolidityFullMath {
    error DenominatorZero();
    error ResultOverflow();

    function mulDiv(uint256 a, uint256 b, uint256 denominator) public pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            if (denominator == 0) revert DenominatorZero();
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        if (denominator <= prod1) revert ResultOverflow();

        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos;
        unchecked {
            twos = (0 - denominator) & denominator;
        }
        assembly {
            denominator := div(denominator, twos)
        }
        assembly {
            prod0 := div(prod0, twos)
        }
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        unchecked {
            prod0 |= prod1 * twos;

            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;

            result = prod0 * inv;
        }
    }

    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) public pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            if (result == type(uint256).max) revert ResultOverflow();
            unchecked {
                result++;
            }
        }
    }
}
