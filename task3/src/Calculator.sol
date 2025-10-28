// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract Calculator{
    uint256 public lastResult;
    // 加法
    function add(uint256 a, uint256 b) public returns (uint256) {
        uint256 result = a + b;
        lastResult = result;
        return result;
    }
    // 减法
    function sub(uint256 a, uint256 b) public returns (uint256) {
        uint256 result = a - b;
        lastResult = result;
        return result;
    }
}