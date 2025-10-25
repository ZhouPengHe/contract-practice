require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("dotenv").config();

module.exports = {
  solidity: "0.8.19",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
  apiKey: process.env.ETHERSCAN_API_KEY,
  customChains: [
    {
      network: "sepolia",
      chainId: 11155111,
      urls: {
        apiURL: "https://api-sepolia.etherscan.io/api",
        browserURL: "https://sepolia.etherscan.io"
      }
    }
  ]
}
};