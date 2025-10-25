require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with account:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance));

  // 部署 MetaNodeToken，初始铸造量 1,000,000 MND (18位精度)
  const initialSupply = ethers.parseUnits("1000000", 18);

  const Token = await ethers.getContractFactory("MetaNodeToken");
  const token = await Token.deploy(initialSupply);

  await token.waitForDeployment();

  console.log("MetaNodeToken deployed to:", await token.getAddress());
  // 合约验证
  await hre.run("verify:verify", {
      address: await token.getAddress(),
      constructorArguments: [initialSupply],
  });
  console.log("Verification successful!");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});