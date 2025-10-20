// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SHIBTokenTestRouter {
    function addLiquidityETH(
        address, uint tokenAmount, uint, uint, address, uint
    ) external payable returns (uint, uint, uint) {
        // 返回和传入一致，确保事件断言正确
        return (tokenAmount, msg.value, 1);
    }

    function factory() external pure returns (address) {
        return address(0);
    }

    function WETH() external pure returns (address) {
        return address(0);
    }
}
