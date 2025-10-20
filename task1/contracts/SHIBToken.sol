// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

// 导入 OpenZeppelin ERC20 标准合约、权限管理 Ownable、地址工具库
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

// 定义与 Uniswap V2 Router 的接口，用于流动性操作和交换
interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    // 添加 Token + ETH 流动性
    function addLiquidityETH(
        address token,               // Token 地址
        uint amountTokenDesired,     // 想要添加的 Token 数量
        uint amountTokenMin,         // 最小添加数量（防滑点）
        uint amountETHMin,           // 最小添加 ETH（防滑点）
        address to,                  // 流动性 token 接收者
        uint deadline                // 截止时间
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    // 支持 Fee-on-transfer 的 Token 与 ETH 交换
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,               // 输入 token 数量
        uint amountOutMin,           // 最小输出 ETH
        address[] calldata path,     // 兑换路径，例如 [Token, WETH]
        address to,                  // 接收 ETH 的地址
        uint deadline                // 截止时间
    ) external;
}

// 主代币合约
contract SHIBToken is ERC20, Ownable {
    using Address for address; // 使用 Address 库的方法（如 isContract）

    // ==== 税率与分配配置 ====
    uint256 public taxBasis = 500;         // 基础交易税率，500 = 5%
    uint256 public liquidityShare = 4000;  // 税中 40% 用于流动性
    uint256 public projectShare = 4000;    // 税中 40% 用于项目钱包
    uint256 public burnShare = 2000;       // 税中 20% 用于燃烧

    address public projectWallet;          // 项目资金接收地址
    address public liquidityReceiver;      // 流动性 token 接收地址（通常是合约自身）

    // ==== 交易限制配置 ====
    uint256 public maxTxAmount;            // 单笔交易最大额度
    uint256 public maxWalletAmount;        // 单个钱包最大持仓

    mapping(address => uint256) public lastTradeTimestamp; // 上一次交易时间，用于冷却限制
    uint256 public tradeCooldown = 30;                       // 交易冷却时间（秒）

    mapping(address => uint256) public dailySpent;          // 当日已交易总额
    mapping(address => uint256) public dailyReset;          // 每日重置时间戳
    uint256 public dailyLimit;                              // 每日交易上限

    // ==== 白名单/免税/免限 ====
    mapping(address => bool) public isExcludedFromFee;     // 免除交易税地址
    mapping(address => bool) public isExcludedFromLimits;  // 免除限制地址（大户、合约操作等）

    // ==== Router 接口 ====
    IUniswapV2Router public router;

    // ==== 事件声明 ====
    event TaxTaken(address indexed from, address indexed to, uint256 taxAmount);      // 税收事件
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);  // 流动性添加事件

    // 构造函数：初始化代币信息、Router、钱包、限制参数
    constructor(
        string memory name_,                 // 代币名称
        string memory symbol_,               // 代币符号
        uint256 totalSupply_,                // 总发行量
        address routerAddr,                  // Uniswap Router 地址
        address projectWallet_               // 项目钱包地址
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, totalSupply_);    // 给部署者铸造总供应量

        router = IUniswapV2Router(routerAddr);  // 设置 Router
        projectWallet = projectWallet_;         // 设置项目钱包
        liquidityReceiver = address(this);      // 默认流动性接收者为合约自身

        // 默认交易限制：1% 单笔交易，2% 单钱包持仓，2% 每日限制
        maxTxAmount = (totalSupply_ * 1) / 100;
        maxWalletAmount = (totalSupply_ * 2) / 100;
        dailyLimit = (totalSupply_ * 2) / 100;

        // 默认白名单：部署者和合约自身免税、免限
        isExcludedFromFee[msg.sender] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
    }

    // ==== 配置函数：可由 owner 调整税率和分配比例 ====
    function setTaxBasis(uint256 _basis) external onlyOwner {
        require(_basis <= 2000, "tax too high"); // 最大 20%
        taxBasis = _basis;
    }

    function setTaxShares(uint256 _liquidityShare, uint256 _projectShare, uint256 _burnShare) external onlyOwner {
        require(_liquidityShare + _projectShare + _burnShare == 10000, "shares must sum 10000"); // 百分比总和 100%
        liquidityShare = _liquidityShare;
        projectShare = _projectShare;
        burnShare = _burnShare;
    }

    function setProjectWallet(address _w) external onlyOwner { projectWallet = _w; }
    function setLiquidityReceiver(address _r) external onlyOwner { liquidityReceiver = _r; }

    function setMaxTx(uint256 _max) external onlyOwner { maxTxAmount = _max; }
    function setMaxWallet(uint256 _max) external onlyOwner { maxWalletAmount = _max; }
    function setTradeCooldown(uint256 _s) external onlyOwner { tradeCooldown = _s; }
    function setDailyLimit(uint256 _amt) external onlyOwner { dailyLimit = _amt; }

    function setRouter(address _r) external onlyOwner { router = IUniswapV2Router(_r); }

    function excludeFromFee(address _a, bool _yes) external onlyOwner { isExcludedFromFee[_a] = _yes; }
    function excludeFromLimits(address _a, bool _yes) external onlyOwner { isExcludedFromLimits[_a] = _yes; }

    // ==== 内部税收逻辑 ====
    function _takeTax(address from, uint256 amount) internal returns (uint256 taxAmount) {
        taxAmount = (amount * taxBasis) / 10000;  // 计算税额
        if (taxAmount == 0) return 0;

        uint256 toLiquidity = (taxAmount * liquidityShare) / 10000; // 分配给流动性
        uint256 toProject = (taxAmount * projectShare) / 10000;     // 分配给项目钱包
        uint256 toBurn = taxAmount - toLiquidity - toProject;       // 剩余燃烧

        if (toLiquidity > 0) {
            _transfer(from, liquidityReceiver, toLiquidity); // 转账到流动性接收者
        }
        if (toProject > 0 && projectWallet != address(0)) {
            _transfer(from, projectWallet, toProject);       // 转账到项目钱包
        }
        if (toBurn > 0) {
            _burn(from, toBurn);                              // 销毁 token
        }

        emit TaxTaken(from, address(this), taxAmount);        // 发出税收事件
        return taxAmount;
    }

    // ==== 转账覆盖函数：增加税收 & 限制 ====
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        // 如果 sender 或 recipient 没有免限，则进行交易限制检查
        if (!isExcludedFromLimits[sender] && !isExcludedFromLimits[recipient]) {
            require(amount <= maxTxAmount, "Exceed max tx amount"); // 单笔限制
            if (!isExcludedFromLimits[recipient]) {
                require(balanceOf(recipient) + amount <= maxWalletAmount, "Exceed max wallet amount"); // 钱包限制
            }

            // 冷却限制
            if (tradeCooldown > 0) {
                uint256 last = lastTradeTimestamp[sender];
                require(block.timestamp >= last + tradeCooldown, "Trade cooldown active");
                lastTradeTimestamp[sender] = block.timestamp;
            }

            // 每日交易限制
            if (dailyLimit > 0) {
                if (block.timestamp >= dailyReset[sender]) {
                    dailyReset[sender] = block.timestamp + 1 days; // 重置时间
                    dailySpent[sender] = 0;                          // 重置每日花费
                }
                require(dailySpent[sender] + amount <= dailyLimit, "Exceed daily limit");
                dailySpent[sender] += amount;                       // 累计每日交易额
            }
        }

        // 检查是否免税
        if (isExcludedFromFee[sender] || isExcludedFromFee[recipient]) {
            super._transfer(sender, recipient, amount); // 直接转账
        } else {
            uint256 tax = _takeTax(sender, amount);      // 扣税
            uint256 afters = amount - tax;                // 实际到账
            super._transfer(sender, recipient, afters);   // 执行转账
        }
    }

    // ==== 添加流动性功能（仅 owner 使用） ====
    function addLiquidityWithETH(uint256 tokenAmount) external payable onlyOwner {
        require(msg.value > 0, "ETH required");  // 确保发送了 ETH
        _approve(address(this), address(router), tokenAmount); // 授权 Router 使用 token
        (uint amountToken, uint amountETH, uint liquidity) = router.addLiquidityETH{value: msg.value}(
            address(this), tokenAmount, 0, 0, owner(), block.timestamp
        );
        emit LiquidityAdded(amountToken, amountETH, liquidity); // 发事件
    }

    // ==== 资金救援 ====
    function rescueETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance); // 提取合约中 ETH
    }

    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount); // 提取合约中任意 ERC20
    }

    // 接收 ETH
    receive() external payable {}
}