# SHIBToken 操作指南

## 一、合约功能简介
SHIBToken 是基于 ERC20 的 Meme 代币，支持：
- **代币税机制**：对普通交易收取税费；
- **流动性事件**：自动触发流动性添加事件；
- **交易限制**：单笔限制、冷却时间、每日上限等。

---

## 二、部署步骤

### 1. 环境准备
- Node.js 版本 >= 18
- Hardhat 环境
```bash
npm install --save-dev hardhat
```

### 2. 合约部署
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

### 3. 合约验证
```bash
npx hardhat verify <contract_address> --network sepolia
```

---

## 三、合约使用说明

### 1. 转账
```js
await token.transfer(receiver, amount);
```

### 2. 白名单管理
```js
await token.excludeFromFee(address, true);
```

### 3. 税率调整
```js
await token.setTaxBasis(300); // 3%
```

### 4. 流动性操作
```js
await token.addLiquidityWithETH();
```

---

## 四、测试说明
测试文件：`test/SHIBToken.test.js`  
执行命令：
```bash
npx hardhat test
```

测试内容包括：
- 税收征收逻辑；
- 白名单免税；
- 交易冷却；
- 流动性事件触发。

---

## 五、注意事项
- 部署前务必检查初始税率与限额配置；
- 不建议将全部代币投入流动性池，以免锁死；
- 调整税率应经过社区投票或治理机制确认。