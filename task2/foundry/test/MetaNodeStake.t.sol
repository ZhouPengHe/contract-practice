// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/Address.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../src/MetaNodeToken.sol";
import "../src/MetaNodeStake.sol";

contract MetaNodeStakeTest is Test {
    // 测试用的 MetaNode ERC20 代币
    MetaNodeToken token;
    // 测试用的质押合约
    MetaNodeStake stake;
    // 合约拥有者地址（部署者）
    address owner;
    // 三个测试用户地址
    address addr1 = address(0x1);
    address addr2 = address(0x2);
    address addr3 = address(0x3);
    // 初始发行量 100 万 MetaNode（单位 ether = 10^18）
    uint256 initialSupply = 1_000_000 ether;

    // 每个测试函数运行前都会调用 setUp() 初始化状态
    function setUp() public {
        // 设置 owner 为测试合约自身
        owner = address(this);
        // 部署 MetaNodeToken 合约
        token = new MetaNodeToken(initialSupply);
        // 设置质押奖励开始块和结束块
        uint256 startBlock = block.number;
        uint256 endBlock = startBlock + 100;
        // 每块奖励 1 MetaNode
        uint256 MetaNodePerBlock = 1 ether;
        // 部署质押合约并初始化
        stake = new MetaNodeStake();
        stake.initialize(token, startBlock, endBlock, MetaNodePerBlock);
        // 给三个测试用户 mint ERC20 代币
        token.mint(addr1, 1000 ether);
        token.mint(addr2, 1000 ether);
        token.mint(addr3, 1000 ether);
    }

    // --------------------- 测试添加池 ---------------------
    function testAddETHPool() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 验证池数量为 1
        assertEq(stake.poolLength(), 1);
    }

    function testAddERC20Pool() public {
        // 先添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 添加 ERC20 池
        stake.addPool(address(token), 50, 10 ether, 1, false);
        // 验证池数量为 2
        assertEq(stake.poolLength(), 2);
    }

    // --------------------- 测试 ETH 存取款流程 ---------------------
    function testDepositAndWithdrawETH() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 给 addr1 分配 10 ETH
        vm.deal(addr1, 10 ether);
        // 模拟 addr1 调用合约
        vm.prank(addr1);
        // addr1 存入 1 ETH
        stake.depositETH{value: 1 ether}();
        // 模拟 addr1 调用合约
        vm.prank(addr1);
        // addr1 申请解除质押 1 ETH
        stake.unstake(0, 1 ether);
        // 模拟区块增加 1 个块
        vm.roll(block.number + 1);
        // 模拟 addr1 调用合约
        vm.prank(addr1);
        // addr1 提取已解锁的 ETH
        stake.withdraw(0);
        // 验证 stakingBalance 是否为 0
        assertEq(stake.stakingBalance(0, addr1), 0);
    }

    // --------------------- 测试 ERC20 存取款流程 ---------------------
    function testDepositAndWithdrawERC20() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 添加 ERC20 池
        stake.addPool(address(token), 100, 10 ether, 1, false);
        // 模拟 addr1
        vm.prank(addr1);
        // 批准合约可以花费 100 ERC20
        token.approve(address(stake), 100 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ERC20 到池子 1
        stake.deposit(1, 100 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 申请解押 ERC20
        stake.unstake(1, 100 ether);
        // 区块增加 1
        vm.roll(block.number + 1);
        // 模拟 addr1
        vm.prank(addr1);
        // 提取已解押 ERC20
        stake.withdraw(1);
        // 验证余额为 0
        assertEq(stake.stakingBalance(1, addr1), 0);
    }

    // --------------------- 测试奖励领取 ---------------------
    function testClaimRewards() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 给 addr1 分配 1 ETH
        vm.deal(addr1, 1 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ETH
        stake.depositETH{value: 1 ether}();
        // 区块增加 1
        vm.roll(block.number + 1);
        // 模拟 addr1
        vm.prank(addr1);
        // 领取奖励
        stake.claim(0);
        // pending 应为 0
        assertEq(stake.pendingMetaNode(0, addr1), 0);
    }

    // --------------------- 测试暂停与恢复 ---------------------
    function testPauseUnpause() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 管理员暂停 withdraw
        stake.pauseWithdraw();
        // 模拟 addr1
        vm.prank(addr1);
        // 断言 withdraw 被暂停
        vm.expectRevert(bytes("withdraw is paused"));
        stake.unstake(0, 1 ether);
        // 恢复 withdraw
        stake.unpauseWithdraw();
        // 模拟 addr1
        vm.prank(addr1);
        // withdraw 恢复正常
        stake.withdraw(0);
        // 给 addr1 1 ETH
        vm.deal(addr1, 1 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ETH
        stake.depositETH{value: 1 ether}();
        // 暂停领取奖励
        stake.pauseClaim();
        // 模拟 addr1
        vm.prank(addr1);
        // 断言 claim 被暂停
        vm.expectRevert(bytes("claim is paused"));
        stake.claim(0);
        // 恢复领取奖励
        stake.unpauseClaim();
        // 模拟 addr1
        vm.prank(addr1);
        // 正常领取奖励
        stake.claim(0);
        // 验证 pendingMetaNode
        assertEq(stake.pendingMetaNode(0, addr1), 0);
    }

    // --------------------- 测试存入低于最小金额 ---------------------
    function testDepositBelowMinimum() public {
        // 设置最小质押 1 ether
        stake.addPool(address(0), 100, 1 ether, 1, false);
        // 给 addr1 0.5 ETH
        vm.deal(addr1, 0.5 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 断言 deposit 被拒绝
        vm.expectRevert(bytes("deposit amount is too small"));
        stake.depositETH{value: 0.5 ether}();
    }

    // --------------------- 测试无效池 ID ---------------------
    function testInvalidPoolID() public {
        // 模拟 addr1
        vm.prank(addr1);
        // 断言 pid 不存在
        vm.expectRevert(bytes("invalid pid"));
        stake.deposit(999, 10);
    }

    // --------------------- 测试提前提现 ---------------------
    function testWithdrawBeforeUnlock() public {
        // 添加 ETH 池，解除质押锁定 10 块
        stake.addPool(address(0), 100, 0.1 ether, 10, false);
        // 给 addr1 分配 1 ETH
        vm.deal(addr1, 1 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ETH
        stake.depositETH{value: 1 ether}();
        // 模拟 addr1
        vm.prank(addr1);
        // 申请解除质押 0.5 ETH
        stake.unstake(0, 0.5 ether);
        // 查询存款前余额
        uint256 balanceBefore = stake.stakingBalance(0, addr1);
        // 模拟 addr1 提取（此时不可提取）
        vm.prank(addr1);
        stake.withdraw(0);
        // 查询存款后余额
        uint256 balanceAfter = stake.stakingBalance(0, addr1);
        // 验证余额未变
        assertEq(balanceAfter, balanceBefore);
    }

    // --------------------- 测试多用户 ERC20 质押 ---------------------
    function testMultiplePoolsERC20() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 添加 ERC20 池
        stake.addPool(address(token), 50, 10 ether, 1, false);
        // 模拟 addr1
        vm.prank(addr1);
        token.approve(address(stake), 50 ether);
        // 存入 ERC20
        vm.prank(addr1);
        stake.deposit(1, 50 ether);
        // 模拟 addr2
        vm.prank(addr2);
        token.approve(address(stake), 30 ether);
        // 存入 ERC20
        vm.prank(addr2);
        stake.deposit(1, 30 ether);
        // 验证余额
        assertEq(stake.stakingBalance(1, addr1), 50 ether);
        assertEq(stake.stakingBalance(1, addr2), 30 ether);
    }

    // --------------------- 测试跨块奖励累积 ---------------------
    function testRewardAccrualOverBlocks() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 给 addr1 分配 2 ETH
        vm.deal(addr1, 2 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ETH
        stake.depositETH{value: 2 ether}();
        // 查询初始 pending 奖励
        uint256 initialPending = stake.pendingMetaNode(0, addr1);
        // 模拟 5 个区块
        vm.roll(block.number + 5);
        // 查询 pending 奖励
        uint256 pendingAfter5 = stake.pendingMetaNode(0, addr1);
        // 验证奖励累积
        assertGt(pendingAfter5, initialPending);
        // 模拟 addr1 领取奖励
        vm.prank(addr1);
        stake.claim(0);
        // 验证 pending 为 0
        assertEq(stake.pendingMetaNode(0, addr1), 0);
    }

    // --------------------- 测试多用户奖励比例 ---------------------
    function testMultipleUsersRewardDistribution() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 分配 ETH 给用户
        vm.deal(addr1, 1 ether);
        vm.deal(addr2, 2 ether);
        // 用户存入 ETH
        vm.prank(addr1);
        stake.depositETH{value: 1 ether}();
        vm.prank(addr2);
        stake.depositETH{value: 2 ether}();
        // 模拟 3 个区块
        vm.roll(block.number + 3);
        // 查询 pending 奖励
        uint256 pending1 = stake.pendingMetaNode(0, addr1);
        uint256 pending2 = stake.pendingMetaNode(0, addr2);
        // 验证奖励比例
        assertGt(pending1, 0);
        assertGt(pending2, 0);
        assertLt(pending1, pending2);
    }

    // --------------------- 管理员权限限制 ---------------------
    function testAdminOnlyFunction() public {
        // 模拟非管理员调用
        vm.prank(addr1);
        // 断言 revert
        vm.expectRevert();
        stake.addPool(address(token), 100, 1 ether, 1, false);
    }

    // --------------------- 紧急暂停/恢复全合约 ---------------------
    function testPauseAll() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 暂停 withdraw 和 claim
        stake.pauseWithdraw();
        stake.pauseClaim();
        // 给 addr1 1 ETH
        vm.deal(addr1, 1 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 验证 withdraw 被暂停
        vm.expectRevert(bytes("withdraw is paused"));
        stake.unstake(0, 1 ether);
        // 验证 claim 被暂停
        vm.prank(addr1);
        vm.expectRevert(bytes("claim is paused"));
        stake.claim(0);
        // 恢复操作
        stake.unpauseWithdraw();
        stake.unpauseClaim();
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ETH
        stake.depositETH{value: 1 ether}();
        // 验证余额
        assertEq(stake.stakingBalance(0, addr1), 1 ether);
    }

    // --------------------- Deposit 事件断言 ---------------------
    function testDepositEvent() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 给 addr1 1 ETH
        vm.deal(addr1, 1 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 期望事件
        vm.expectEmit(true, true, true, true);
        emit MetaNodeStake.Deposit(addr1, 0, 1 ether);
        // 调用触发事件
        stake.depositETH{value: 1 ether}();
    }

    // --------------------- Claim 事件断言 ---------------------
    function testClaimEvent() public {
        // 添加 ETH 池
        stake.addPool(address(0), 100, 0.1 ether, 1, false);
        // 给 addr1 1 ETH
        vm.deal(addr1, 1 ether);
        // 模拟 addr1
        vm.prank(addr1);
        // 存入 ETH
        stake.depositETH{value: 1 ether}();
        // 区块增长
        vm.roll(block.number + 1);
        // 模拟 addr1
        vm.prank(addr1);
        // 期望事件
        vm.expectEmit(true, true, true, true);
        emit MetaNodeStake.Claim(addr1, 0, 1 ether);
        // 调用触发事件
        stake.claim(0);
    }
}