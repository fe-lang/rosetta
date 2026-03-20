// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Simple constant-product AMM (x * y = k).
/// Equivalent to the Fe SimpleAmm — same logic, same storage layout.
contract SoliditySimpleAmm {
    uint256 public reserveA;
    uint256 public reserveB;

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        reserveA += amountA;
        reserveB += amountB;
    }

    function swapAForB(uint256 amountIn) external returns (uint256 amountOut) {
        if (amountIn == 0 || reserveA == 0 || reserveB == 0) return 0;
        amountOut = reserveB * amountIn / (reserveA + amountIn);
        if (amountOut == 0) return 0;
        reserveA += amountIn;
        reserveB -= amountOut;
    }

    function swapBForA(uint256 amountIn) external returns (uint256 amountOut) {
        if (amountIn == 0 || reserveA == 0 || reserveB == 0) return 0;
        amountOut = reserveA * amountIn / (reserveB + amountIn);
        if (amountOut == 0) return 0;
        reserveB += amountIn;
        reserveA -= amountOut;
    }

    function getReserveA() external view returns (uint256) { return reserveA; }
    function getReserveB() external view returns (uint256) { return reserveB; }
    function getK() external view returns (uint256) { return reserveA * reserveB; }
}
