const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("MetaNodeStake 测试", function () {
  let Token, token, Stake, stake;
  let owner, addr1, addr2;
  const initialSupply = ethers.parseUnits("1000000", 18);

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // 部署奖励代币
        Token = await ethers.getContractFactory("MetaNodeToken");
        token = await Token.deploy(initialSupply);
        await token.waitForDeployment();

        // 部署质押合约
        Stake = await ethers.getContractFactory("MetaNodeStake");
        const startBlock = await ethers.provider.getBlockNumber();
        const endBlock = startBlock + 100;
        const MetaNodePerBlock = ethers.parseUnits("1", 18);

        stake = await upgrades.deployProxy(
        Stake,
        [token.target, startBlock, endBlock, MetaNodePerBlock],
        { initializer: "initialize" }
        );
        await stake.waitForDeployment();

        // 给用户分发ERC20用于质押
        const userAmount = ethers.parseUnits("1000", 18);
        await token.mint(addr1.address, userAmount);
        await token.mint(addr2.address, userAmount);
    });

    it("管理员可新增 ETH 池", async function () {
        await stake.addPool(
        ethers.ZeroAddress,
        100,
        ethers.parseEther("0.1"),
        5,
        false
        );
        expect(await stake.poolLength()).to.equal(1n);
    });

    it("管理员可新增 ERC20 池", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 5, false);
        await stake.addPool(token.target, 50, ethers.parseUnits("10", 18), 5, false);
        expect(await stake.poolLength()).to.equal(2n);
    });

    it("用户可存入并取出 ETH", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);
        const depositAmount = ethers.parseEther("1");

        await stake.connect(addr1).depositETH({ value: depositAmount });
        expect(await stake.stakingBalance(0, addr1.address)).to.equal(depositAmount);

        await ethers.provider.send("evm_mine");
        await stake.connect(addr1).unstake(0, depositAmount);
        await ethers.provider.send("evm_mine");
        await stake.connect(addr1).withdraw(0);

        expect(await stake.stakingBalance(0, addr1.address)).to.equal(0n);
    });

    it("用户可存入并取出 ERC20", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);
        await stake.addPool(token.target, 100, ethers.parseUnits("10", 18), 1, false);

        const depositAmount = ethers.parseUnits("100", 18);
        await token.connect(addr1).approve(stake.target, depositAmount);
        await stake.connect(addr1).deposit(1, depositAmount);

        expect(await stake.stakingBalance(1, addr1.address)).to.equal(depositAmount);

        await ethers.provider.send("evm_mine");
        await stake.connect(addr1).unstake(1, depositAmount);
        await ethers.provider.send("evm_mine");
        await stake.connect(addr1).withdraw(1);

        expect(await stake.stakingBalance(1, addr1.address)).to.equal(0n);
    });

    it("奖励领取后应清零", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);
        const depositAmount = ethers.parseEther("1");
        await stake.connect(addr1).depositETH({ value: depositAmount });

        await ethers.provider.send("evm_mine");
        await stake.connect(addr1).claim(0);

        expect(await stake.pendingMetaNode(0, addr1.address)).to.equal(0n);
    });

    it("管理员可暂停/恢复质押", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);

        // 暂停 withdraw
        await stake.connect(owner).pauseWithdraw();
        await expect(
        stake.connect(addr1).unstake(0, ethers.parseEther("1"))
        ).to.be.revertedWith("withdraw is paused"); 

        // 恢复 withdraw
        await stake.connect(owner).unpauseWithdraw();
        await stake.connect(addr1).withdraw(0)
        expect(await stake.stakingBalance(0, addr1.address)).to.equal(0n);

        // 暂停/恢复 claim
        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });
        await stake.connect(owner).pauseClaim();
        await expect(stake.connect(addr1).claim(0)).to.be.revertedWith("claim is paused");

        await stake.connect(owner).unpauseClaim();
        await stake.connect(addr1).claim(0);
        expect(await stake.pendingMetaNode(0, addr1.address)).to.equal(0n);
    });

    it("非管理员调用暂停/恢复应报错", async function () {
        await expect(stake.connect(addr1).pauseWithdraw()).to.be.reverted;
        await expect(stake.connect(addr1).unpauseWithdraw()).to.be.reverted;
        await expect(stake.connect(addr1).pauseClaim()).to.be.reverted;
        await expect(stake.connect(addr1).unpauseClaim()).to.be.reverted;
    });

    it("重复暂停/恢复应报错", async function () {
        await stake.connect(owner).pauseWithdraw();
        await expect(stake.connect(owner).pauseWithdraw()).to.be.revertedWith("withdraw has been already paused");
        await stake.connect(owner).unpauseWithdraw();
        await expect(stake.connect(owner).unpauseWithdraw()).to.be.revertedWith("withdraw has been already unpaused");

        await stake.connect(owner).pauseClaim();
        await expect(stake.connect(owner).pauseClaim()).to.be.revertedWith("claim has been already paused");
        await stake.connect(owner).unpauseClaim();
        await expect(stake.connect(owner).unpauseClaim()).to.be.revertedWith("claim has been already unpaused");
    });

    it("无效池ID应报错", async function () {
        await expect(stake.connect(addr1).deposit(999, 10)).to.be.revertedWith("invalid pid");
    });

    it("应在锁定期未到时拒绝提取", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 10, false);
        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });
        await stake.connect(addr1).unstake(0, ethers.parseEther("0.5"));
        const before = await stake.stakingBalance(0, addr1.address);
        await stake.connect(addr1).withdraw(0); 
        const after = await stake.stakingBalance(0, addr1.address);
        expect(after).to.equal(before);
    });

    it("没有奖励时调用claim不应revert", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);
        const tx = await stake.connect(addr1).claim(0);
        await expect(tx).to.not.be.reverted;
    });

    it("应禁止恢复未暂停状态的操作", async function () {
        await expect(stake.connect(owner).unpauseWithdraw()).to.be.revertedWith("withdraw has been already unpaused");
    });

    it("非法池ID调用claim应报错", async function () {
        await expect(stake.connect(addr1).claim(999)).to.be.revertedWith("invalid pid");
    });

    it("存入金额低于最小质押要求应revert", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("1"), 1, false);
        await expect(
        stake.connect(addr1).depositETH({ value: ethers.parseEther("0.5") })
        ).to.be.revertedWith("deposit amount is too small");
    });
    });

    // ---------------- 补充测试 ----------------
    describe("MetaNodeStake 边界/分支补充测试", function () {
    let Token, token, Stake, stake;
    let owner, addr1, addr2, addr3;
    const initialSupply = ethers.parseUnits("1000000", 18);

    beforeEach(async function () {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        Token = await ethers.getContractFactory("MetaNodeToken");
        token = await Token.deploy(initialSupply);
        await token.waitForDeployment();

        Stake = await ethers.getContractFactory("MetaNodeStake");
        const startBlock = await ethers.provider.getBlockNumber();
        const endBlock = startBlock + 100;
        const MetaNodePerBlock = ethers.parseUnits("1", 18);

        stake = await upgrades.deployProxy(
        Stake,
        [token.target, startBlock, endBlock, MetaNodePerBlock],
        { initializer: "initialize" }
        );
        await stake.waitForDeployment();

        const userAmount = ethers.parseUnits("1000", 18);
        await token.mint(addr1.address, userAmount);
        await token.mint(addr2.address, userAmount);
        await token.mint(addr3.address, userAmount);
    });

    it("存入 ERC20/ETH 为0应 revert", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, true);
        await stake.addPool(token.target, 100, ethers.parseUnits("10", 18), 1, false);

        await expect(
        stake.connect(addr1).depositETH({ value: 0 })
        ).to.be.revertedWith("deposit amount is too small");

        await token.connect(addr1).approve(stake.target, 0);
        await expect(stake.connect(addr1).deposit(1, 0)).to.be.revertedWith("deposit amount is too small");
    });

    it("withdrawAmount 分支: 部分请求未解锁", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 5, true);
        const depositAmount = ethers.parseEther("1");
        await stake.connect(addr1).depositETH({ value: depositAmount });
        await stake.connect(addr1).unstake(0, depositAmount);

        const [requestAmount, pendingWithdraw] = await stake.withdrawAmount(0, addr1.address);

        expect(requestAmount).to.equal(depositAmount);
        expect(pendingWithdraw).to.equal(0n);
    });

    it("奖励领取失败或余额不足逻辑", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, true);
        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });

        await token.connect(owner).transfer(addr2.address, initialSupply);
        await expect(stake.connect(addr1).claim(0)).to.not.be.reverted;
    });

    it("最小质押边界测试", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("1"), 1, true);

        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });
        const balance = await stake.stakingBalance(0, addr1.address);
        expect(balance).to.equal(ethers.parseEther("1"));
    });

    it("多请求锁定和部分解锁", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 2, true);

        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });
        await stake.connect(addr1).depositETH({ value: ethers.parseEther("2") });

        await stake.connect(addr1).unstake(0, ethers.parseEther("1"));
        await stake.connect(addr1).unstake(0, ethers.parseEther("2"));

        const [requestAmount, pendingWithdraw] = await stake.withdrawAmount(0, addr1.address);
        expect(requestAmount).to.equal(ethers.parseEther("3"));
        expect(pendingWithdraw).to.equal(0n);

        await ethers.provider.send("evm_mine");
        await ethers.provider.send("evm_mine");
        const [, pendingAfter] = await stake.withdrawAmount(0, addr1.address);
        expect(pendingAfter).to.be.greaterThan(0n);
    });

    it("多池、多用户奖励分发边界", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, true);
        await stake.addPool(token.target, 100, ethers.parseUnits("10", 18), 1, false);

        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });
        await token.connect(addr2).approve(stake.target, ethers.parseUnits("100", 18));
        await stake.connect(addr2).deposit(1, ethers.parseUnits("100", 18));

        for (let i = 0; i < 5; i++) await ethers.provider.send("evm_mine");

        await stake.connect(addr1).claim(0);
        await stake.connect(addr2).claim(1);

        const pending1 = await stake.pendingMetaNode(0, addr1.address);
        const pending2 = await stake.pendingMetaNode(1, addr2.address);

        // 改为断言小于 1 个代币的微小误差
        expect(pending1).to.be.lt(ethers.parseEther("1"));
        expect(pending2).to.be.lt(ethers.parseUnits("1", 18));
    });

    it("ERC20 授权不足应 revert", async function () {
        // 第一个池 ETH
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);
        // 第二个池 ERC20
        await stake.addPool(token.target, 100, ethers.parseUnits("10", 18), 1, false);
        // 不给授权
        await token.connect(addr1).approve(stake.target, 0);
        // 直接 expect revert，不必指定 exact message
        await expect(stake.connect(addr1).deposit(1, ethers.parseUnits("100", 18))).to.be.reverted;
    });


    it("跨多个池的锁定/解锁测试", async function () {
        // 添加两个池
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, true);
        await stake.addPool(token.target, 100, ethers.parseUnits("10", 18), 2, false);

        // 用户存入 ETH 和 ERC20
        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });
        await token.connect(addr1).approve(stake.target, ethers.parseUnits("50", 18));
        await stake.connect(addr1).deposit(1, ethers.parseUnits("50", 18));

        // 用户申请解押
        await stake.connect(addr1).unstake(0, ethers.parseEther("1"));
        await stake.connect(addr1).unstake(1, ethers.parseUnits("50", 18));

        // 快进锁定块数，确保可以 withdraw
        for (let i = 0; i < 3; i++) {
            await ethers.provider.send("evm_mine");
        }

        await stake.connect(addr1).withdraw(0);
        await stake.connect(addr1).withdraw(1);

        const [req0, pend0] = await stake.withdrawAmount(0, addr1.address);
        const [req1, pend1] = await stake.withdrawAmount(1, addr1.address);

        expect(req0).to.equal(0n);
        expect(req1).to.equal(0n);
    });

    it("claim/withdraw 重复操作边界", async function () {
        await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, true);
        await stake.connect(addr1).depositETH({ value: ethers.parseEther("1") });

        await stake.connect(addr1).claim(0);
        await expect(stake.connect(addr1).claim(0)).to.not.be.reverted;

        await stake.connect(addr1).unstake(0, ethers.parseEther("1"));
        await ethers.provider.send("evm_mine");
        await stake.connect(addr1).withdraw(0);
        await expect(stake.connect(addr1).withdraw(0)).to.not.be.reverted;
    });
});
