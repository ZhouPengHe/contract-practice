// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/Calculator.sol";

contract CalculatorTest is Test {
    Calculator calculator;
    function setUp() public {
        calculator = new Calculator();
    }
    function testAdd() public {
        assertEq(calculator.add(5, 3), 8);
    }
    function testSub() public {
        assertEq(calculator.sub(10, 6), 4);
    }
}
