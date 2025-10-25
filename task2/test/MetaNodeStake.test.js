const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

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

  it("✅ 管理员可新增 ETH 池", async function () {
    await stake.addPool(
      ethers.ZeroAddress,
      100,
      ethers.parseEther("0.1"),
      5,
      false
    );
    expect(await stake.poolLength()).to.equal(1n);
  });

  it("✅ 管理员可新增 ERC20 池", async function () {
    await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 5, false);
    await stake.addPool(token.target, 50, ethers.parseUnits("10", 18), 5, false);
    expect(await stake.poolLength()).to.equal(2n);
  });

  it("✅ 用户可存入并取出 ETH", async function () {
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

  it("✅ 用户可存入并取出 ERC20", async function () {
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

  it("✅ 奖励领取后应清零", async function () {
    await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);
    const depositAmount = ethers.parseEther("1");
    await stake.connect(addr1).depositETH({ value: depositAmount });

    await ethers.provider.send("evm_mine");
    await stake.connect(addr1).claim(0);

    expect(await stake.pendingMetaNode(0, addr1.address)).to.equal(0n);
  });

  it("✅ 管理员可暂停/恢复质押", async function () {
    await stake.addPool(ethers.ZeroAddress, 100, ethers.parseEther("0.1"), 1, false);

    // 暂停 withdraw
    await stake.connect(owner).pauseWithdraw();
    await expect(
      stake.connect(addr1).unstake(0, ethers.parseEther("1"))
    ).to.be.revertedWith("withdraw is paused"); // 或 revert message 匹配

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

  it("✅ 非管理员调用暂停/恢复应报错", async function () {
    await expect(stake.connect(addr1).pauseWithdraw()).to.be.reverted;
    await expect(stake.connect(addr1).unpauseWithdraw()).to.be.reverted;
    await expect(stake.connect(addr1).pauseClaim()).to.be.reverted;
    await expect(stake.connect(addr1).unpauseClaim()).to.be.reverted;
  });

  it("✅ 重复暂停/恢复应报错", async function () {
    await stake.connect(owner).pauseWithdraw();
    await expect(stake.connect(owner).pauseWithdraw()).to.be.revertedWith("withdraw has been already paused");
    await stake.connect(owner).unpauseWithdraw();
    await expect(stake.connect(owner).unpauseWithdraw()).to.be.revertedWith("withdraw has been already unpaused");

    await stake.connect(owner).pauseClaim();
    await expect(stake.connect(owner).pauseClaim()).to.be.revertedWith("claim has been already paused");
    await stake.connect(owner).unpauseClaim();
    await expect(stake.connect(owner).unpauseClaim()).to.be.revertedWith("claim has been already unpaused");
  });

  it("✅ 无效池ID应报错", async function () {
    await expect(stake.connect(addr1).deposit(999, 10)).to.be.revertedWith("invalid pid");
  });
});
