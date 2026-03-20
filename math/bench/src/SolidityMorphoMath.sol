// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @dev Morpho Blue MathLib + SharesMathLib, adapted as a contract for benchmarking.
/// Original: https://github.com/morpho-org/morpho-blue/blob/main/src/libraries/MathLib.sol
///           https://github.com/morpho-org/morpho-blue/blob/main/src/libraries/SharesMathLib.sol
contract SolidityMorphoMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    function mulDivDown(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return (x * y) / d;
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) public pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    function wMulDown(uint256 x, uint256 y) external pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function wDivDown(uint256 x, uint256 y) external pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    function wDivUp(uint256 x, uint256 y) external pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    function wTaylorCompounded(uint256 x, uint256 n) external pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);
        return firstTerm + secondTerm + thirdTerm;
    }

    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return mulDivDown(assets, totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return mulDivDown(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }
}
