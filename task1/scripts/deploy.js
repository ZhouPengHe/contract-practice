const hre = require("hardhat");

async function main() {
  // 获取部署账户
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with account:", deployer.address);

  // 获取账户余额
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "ETH");

  // 获取合约工厂
  const SHIBToken = await hre.ethers.getContractFactory("SHIBToken");

  // 参数说明：
  // name: "MemeToken"
  // symbol: "MEME"
  // totalSupply: 1_000_000_000 * 10**18
  // routerAddr: Uniswap V2 Router 地址（测试网可用官方 Router）
  // projectWallet: 部署者地址作为示例
  const token = await SHIBToken.deploy(
    "MemeToken",
    "MEME",
    hre.ethers.parseEther("1000000000"), // ✅ v6: parseEther 直接挂在 ethers 下
    "0x1b02da8cb0d097eb8d57a175b88c7d8b47997506", // 示例 Router 地址（SushiSwap Sepolia）
    deployer.address
  );

  // 等待部署完成
  await token.waitForDeployment();

  console.log("SHIBToken deployed to:", await token.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
