const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SHIBToken", function () {
  let owner, addr1, addr2;
  let SHIBToken, token;
  let totalSupply;

  // Mock Router
  let MockRouter, router;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // 部署 Mock Router
    MockRouter = await ethers.getContractFactory("SHIBTokenTestRouter");
    router = await MockRouter.deploy();
    await router.waitForDeployment();

    // 部署 SHIBToken
    SHIBToken = await ethers.getContractFactory("SHIBToken");
    totalSupply = ethers.parseEther("1000000"); // 1,000,000 token
    token = await SHIBToken.deploy(
      "SHIBToken",
      "SHIB",
      totalSupply,
      router.target,
      owner.address
    );
    await token.waitForDeployment();
  });

  it("✅ 总供应量分配给部署者", async function () {
    expect(await token.balanceOf(owner.address)).to.equal(totalSupply);
  });

  it("✅ 部署者转账时免税", async function () {
    await token.transfer(addr1.address, ethers.parseEther("1000"));
    expect(await token.balanceOf(addr1.address)).to.equal(
      ethers.parseEther("1000")
    );
  });

  it("✅ 非免税账户转账应收税", async function () {
    // addr1 先接收 token
    await token.transfer(addr1.address, ethers.parseEther("1000"));
    // addr1 转给 addr2
    await token.connect(addr1).transfer(addr2.address, ethers.parseEther("1000"));
    const tax = ethers.parseEther("50"); // 5% 税
    expect(await token.balanceOf(addr2.address)).to.equal(
      ethers.parseEther("950")
    );
  });

  it("✅ 超出单笔限制应 revert", async function () {
    const maxTx = await token.maxTxAmount();
    // 先把 token 给 addr1，再让 addr1 转给 addr2 超过 maxTx
    await token.transfer(addr1.address, maxTx + 10n);
    await expect(
      token.connect(addr1).transfer(addr2.address, maxTx + 1n)
    ).to.be.revertedWith("Exceed max tx amount");
  });

  it("✅ 日交易限额生效", async function () {
    const dailyLimit = await token.dailyLimit();
    // 先转给 addr1 足够金额
    await token.transfer(addr1.address, dailyLimit + 10n);
    // addr1 第一次转账
    await token.connect(addr1).transfer(addr2.address, dailyLimit / 2n);
    // 快进时间，跳过 cooldown
    await ethers.provider.send("evm_increaseTime", [3600]); // 假设 cooldown=1小时
    await ethers.provider.send("evm_mine"); // 生成新块
    // addr1 第二次转账
    await token.connect(addr1).transfer(addr2.address, dailyLimit / 2n);
    // 再一次超出 dailyLimit
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");
    await expect(
      token.connect(addr1).transfer(addr2.address, 1n)
    ).to.be.revertedWith("Exceed daily limit");
  });

  it("✅ 冷却时间限制生效", async function () {
    const amount = ethers.parseEther("10");
    await token.transfer(addr1.address, amount);
    await token.connect(addr1).transfer(addr2.address, amount);
    // 立即再转应该失败
    await expect(
      token.connect(addr1).transfer(addr2.address, amount)
    ).to.be.revertedWith("Trade cooldown active");
  });

  it("✅ 白名单免税/免限生效", async function () {
    await token.excludeFromFee(addr1.address, true);
    await token.excludeFromLimits(addr1.address, true);
    const amount = ethers.parseEther("100000");
    await token.transfer(addr1.address, amount);
    await token.connect(addr1).transfer(addr2.address, amount); // 不触发限制
    expect(await token.balanceOf(addr2.address)).to.equal(amount);
  });

  it("✅ 添加流动性事件触发", async function () {
    const amount = ethers.parseEther("1000");
    const ethAmount = ethers.parseEther("1");
    await expect(token.addLiquidityWithETH(amount, { value: ethAmount }))
      .to.emit(token, "LiquidityAdded")
      .withArgs(amount, ethAmount, 1); // 返回值和事件一致
  });
  
});
