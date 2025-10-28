// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/CalculatorOptimized.sol";

contract CalculatorTest is Test {
    CalculatorOptimized calc;

    function setUp() public {
        calc = new CalculatorOptimized();
    }

    function testAdd() public view {
        uint256 res = calc.add(1, 2);
        assertEq(res, 3);
    }

    function testSub() public view {
        uint256 res = calc.sub(5, 3);
        assertEq(res, 2);
    }
}