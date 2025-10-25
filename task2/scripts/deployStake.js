require("dotenv").config();
const { ethers, upgrades} = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with account:", deployer.address);

  // 设置参数
  const MetaNodeAddress = "0x1D651d617f47466A6CbF0B9F483912c58E5D863A";
  const startBlock = await ethers.provider.getBlockNumber(); // 当前区块作为起始
  const endBlock = startBlock + 100000; // 结束区块，可根据需要调整
  const MetaNodePerBlock = ethers.parseUnits("1", 18); // 每区块奖励1 MND

  // 部署可升级合约
  const Stake = await ethers.getContractFactory("MetaNodeStake");
  const stake = await upgrades.deployProxy(
    Stake,
    [MetaNodeAddress, startBlock, endBlock, MetaNodePerBlock],
    { initializer: "initialize" }
  );

  await stake.waitForDeployment();
  // 0x7DA3af5B1665c86bFCe61418734660D6f9ae0524
  console.log("MetaNodeStake deployed to:", await stake.getAddress());

  // 获取逻辑合约地址
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(await stake.getAddress());
  console.log("Verifying implementation contract:", implementationAddress);

  // 验证逻辑合约
  await hre.run("verify:verify", {
    address: implementationAddress,
    constructorArguments: [], // 逻辑合约没有构造参数
  });

  console.log("Deployment and verification finished!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });