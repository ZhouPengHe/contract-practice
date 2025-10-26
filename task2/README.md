# MetaNode Stake System

## 项目概述
MetaNode Stake 系统是一个基于以太坊的质押和奖励智能合约系统，包括两个主要合约：
1. **MetaNodeToken (MND)**: ERC20 奖励代币合约。
2. **MetaNodeStake**: 支持 ETH/ERC20 质押的质押池合约，用户可领取 MND 奖励。

系统特点：
- 支持多池质押，每个池可单独配置最小质押、锁定期和权重。
- 奖励按区块累积发放，池权重影响奖励分配。
- 支持合约升级（UUPS）、暂停操作、访问控制。
- 完全事件记录，便于前端和链上监听。
---

![Coverage](https://img.shields.io/badge/coverage-90%25-brightgreen)

## 测试覆盖率

- **MetaNodeStake.sol**: 90.6% 语句覆盖率, 57.53% 分支覆盖率
- **MetaNodeToken.sol**: 100% 覆盖率

覆盖率报告生成于 [`./coverage/index.html`](./coverage/index.html)，可在浏览器中打开查看详细报告。





## 项目结构

```text
task2/
│
├─ contracts/
│   ├─ MetaNodeToken.sol       # 奖励代币合约
│   └─ MetaNodeStake.sol       # 质押合约
│
├─ scripts/
│   ├─ deployToken.js          # 部署 MetaNodeToken 合约
│   └─ deployStake.js          # 部署 MetaNodeStake 合约
│
├─ test/
│   ├─ MetaNodeToken.test.js   # Token 测试用例
│   └─ MetaNodeStake.test.js   # Stake 合约测试用例（覆盖率100%）
│
├─ .env                        # 环境变量配置
├─ hardhat.config.js            # Hardhat 配置
└─ README.md                    # 开发者操作指南
```

---

## 安装依赖

确保本地环境安装：
- Node.js >= 18
- npm 或 yarn
- Hardhat
- Ganache/Hardhat 内置本地网络（可选）

安装项目依赖：

```bash
npm install
```

---

## 环境变量配置 (.env)

在项目根目录创建 `.env` 文件：

```text
# 以太坊私钥，用于部署合约
PRIVATE_KEY="你的钱包私钥"

# RPC URL，可以使用 Infura/Alchemy 的 Sepolia 节点
SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/你的项目ID"

# Etherscan API Key，用于合约验证
ETHERSCAN_API_KEY="你的EtherscanAPIKey"
```

⚠️ 注意：**切勿上传或泄露私钥**。

---

## 合约部署

### 部署奖励代币 MetaNodeToken

```bash
npx hardhat run scripts/deployToken.js --network sepolia
```

部署完成后会输出：
- 合约地址
- 初始铸造数量

### 部署质押合约 MetaNodeStake

```bash
npx hardhat run scripts/deployStake.js --network sepolia
```

部署参数：
- MetaNodeToken 合约地址
- 起始区块号 `startBlock`
- 结束区块号 `endBlock`
- 每区块奖励 `MetaNodePerBlock`

---

## 合约验证

使用 Hardhat 合约验证插件：

```bash
npx hardhat verify --network sepolia <合约地址> <构造函数参数...>
```

示例：

```bash
npx hardhat verify --network sepolia 0xYourTokenAddress 1000000000000000000000000
```

---

## 使用指南

### 质押
- **ETH 质押**：
```js
await stakeContract.depositETH({ value: ethers.utils.parseEther("1") });
```

- **ERC20 质押**：
```js
await tokenContract.approve(stakeContract.address, amount);
await stakeContract.deposit(poolId, amount);
```

### 解质押
```js
await stakeContract.unstake(poolId, amount);
await stakeContract.withdraw(poolId);
```

### 领取奖励
```js
await stakeContract.claim(poolId);
```

### 管理员操作
- 添加/更新池
- 设置权重
- 暂停/恢复提现和领奖
- 合约升级（UUPS）

---

## 测试

```bash
npm test
```