const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MetaNodeToken 合约测试", function () {
  let Token, token, owner, addr1, addr2;
  const initialSupply = ethers.parseUnits("1000000", 18);

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    Token = await ethers.getContractFactory("MetaNodeToken");
    token = await Token.deploy(initialSupply);
    await token.waitForDeployment();
  });

  it("名称与符号应正确", async function () {
    expect(await token.name()).to.equal("MetaNodeToken");
    expect(await token.symbol()).to.equal("MND");
    expect(await token.decimals()).to.equal(18);
  });

  it("初始发行量应分配给部署者", async function () {
    const ownerBalance = await token.balanceOf(owner.address);
    expect(ownerBalance).to.equal(initialSupply);
  });

  it("仅管理员可增发代币", async function () {
    const mintAmount = ethers.parseUnits("1000", 18);
    await token.mint(addr1.address, mintAmount);
    expect(await token.balanceOf(addr1.address)).to.equal(mintAmount);
  });

  it("非管理员不能增发代币", async function () {
    const mintAmount = ethers.parseUnits("1000", 18);
    await expect(
      token.connect(addr1).mint(addr1.address, mintAmount)
    ).to.be.revertedWithCustomError;
  });

  it("支持正常转账功能", async function () {
    const transferAmount = ethers.parseUnits("500", 18);
    await token.transfer(addr1.address, transferAmount);
    expect(await token.balanceOf(addr1.address)).to.equal(transferAmount);
    expect(await token.balanceOf(owner.address)).to.equal(initialSupply - transferAmount);
  });
});
