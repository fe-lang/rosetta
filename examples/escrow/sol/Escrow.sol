// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Simple 3-party escrow: depositor, beneficiary, arbiter.
/// Behaviorally equivalent to the Fe version for gas comparison.
contract Escrow {
    address public depositor;
    address public beneficiary;
    address public arbiter;
    uint256 public balance;
    uint256 public state; // 0=empty, 1=funded, 2=released

    constructor(address _beneficiary, address _arbiter) {
        depositor = msg.sender;
        beneficiary = _beneficiary;
        arbiter = _arbiter;
    }

    function deposit() external payable {
        require(state == 0, "already funded");
        balance = msg.value;
        state = 1;
    }

    function release() external returns (uint256) {
        require(msg.sender == arbiter, "not arbiter");
        require(state == 1, "not funded");
        state = 2;
        uint256 amount = balance;
        balance = 0;
        return amount;
    }

    function getBalance() external view returns (uint256) {
        return balance;
    }

    function getState() external view returns (uint256) {
        return state;
    }
}

/// Arbiter proxy — a separate contract that can only call release.
/// In Solidity, nothing prevents this contract from also reading storage,
/// emitting events, or doing anything else. The restriction is by convention.
contract Arbiter {
    function doRelease(address escrow) external returns (uint256) {
        return Escrow(escrow).release();
    }
}
