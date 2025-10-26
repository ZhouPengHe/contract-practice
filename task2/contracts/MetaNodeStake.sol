// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MetaNodeStake is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    // 使用 SafeERC20 的函数扩展到 IERC20 类型，保证 ERC20 转账安全
    using SafeERC20 for IERC20;
    // 使用 Address 工具库为 address 类型添加辅助方法
    using Address for address;
    // 使用 Math 库为 uint256 提供额外数学工具（如果有使用）
    using Math for uint256;

    // ************************************** INVARIANT **************************************

    // 定义管理员角色的常量哈希标识
    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    // 定义升级权限角色的常量哈希标识
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    // 定义 ETH 在池数组中的 pid（第 0 个池为 ETH）
    uint256 public constant ETH_PID = 0;
    
    // ************************************** DATA STRUCTURE **************************************
    // 定义池的信息结构体：包含抵押代币地址、权重、上次奖励块、累积每 ST 的 MetaNode、池内 ST 数量、最小抵押量、解押锁定块数
    struct Pool {
        // 抵押代币地址（ETH 为 address(0x0)）
        address stTokenAddress;
        // 池权重，用于按权重分配奖励
        uint256 poolWeight;
        // 上一次分发 MetaNodes 的区块号
        uint256 lastRewardBlock;
        // 每单位抵押代币累计的 MetaNode（放大了 1 ether，便于精度控制）
        uint256 accMetaNodePerST;
        // 池内抵押代币总量
        uint256 stTokenAmount;
        // 最小存入量
        uint256 minDepositAmount;
        // 取回锁定的块数量（请求 unstake 后需要等待的块数）
        uint256 unstakeLockedBlocks;
    }

    // 定义解押请求结构体：请求数量以及可释放的块号
    struct UnstakeRequest {
        // 请求解押的数量
        uint256 amount;
        // 请求解押后在该区块号可释放
        uint256 unlockBlocks;
    }

    // 定义用户信息结构体：用户抵押量、已发放的 MetaNode、待领取的 MetaNode、解押请求数组
    struct User {
        // 用户提供的抵押代币数量
        uint256 stAmount;
        // 已经分发给用户（已结算）的 MetaNode 数量
        uint256 finishedMetaNode;
        // 已计算但未发放的待领取 MetaNode（deposit/unstake 时会累加到这里）
        uint256 pendingMetaNode;
        // 用户的解押请求列表
        UnstakeRequest[] requests;
    }

    // ************************************** STATE VARIABLES **************************************
    // 第一个开始分发奖励的区块号
    uint256 public startBlock;
    // 最后一个分发奖励的区块号（之后不再分发奖励）
    uint256 public endBlock;
    // 每个区块分发的 MetaNode 数量
    uint256 public MetaNodePerBlock;

    // 是否暂停提现（withdraw）功能的布尔开关
    bool public withdrawPaused;
    // 是否暂停领取（claim）功能的布尔开关
    bool public claimPaused;

    // MetaNode 代币合约实例（ERC20）
    IERC20 public MetaNode;

    // 总的池权重（所有池权重之和）
    uint256 public totalPoolWeight;
    // 池数组
    Pool[] public pool;

    // 池 id => 用户地址 => 用户信息的映射
    mapping (uint256 => mapping (address => User)) public user;

    // ************************************** EVENT **************************************

    // 当设置 MetaNode 合约地址时触发事件
    event SetMetaNode(IERC20 indexed MetaNode);

    // 暂停提现事件
    event PauseWithdraw();

    // 取消暂停提现事件
    event UnpauseWithdraw();

    // 暂停领取事件
    event PauseClaim();

    // 取消暂停领取事件
    event UnpauseClaim();

    // 设置开始块事件
    event SetStartBlock(uint256 indexed startBlock);

    // 设置结束块事件
    event SetEndBlock(uint256 indexed endBlock);

    // 设置每块奖励事件
    event SetMetaNodePerBlock(uint256 indexed MetaNodePerBlock);

    // 添加池事件
    event AddPool(address indexed stTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks);

    // 更新池信息事件（最小存入量与锁定块数）
    event UpdatePoolInfo(uint256 indexed poolId, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks);

    // 设置池权重事件
    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);

    // 更新池（acc、lastReward）事件
    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalMetaNode);

    // 存款事件
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    // 请求解押事件
    event RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount);

    // 提取已解押代币事件
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber);

    // 领取奖励事件
    event Claim(address indexed user, uint256 indexed poolId, uint256 MetaNodeReward);

    // ************************************** MODIFIER **************************************

    // 检查 pid 是否有效（小于池数组长度）
    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "invalid pid");
        _;
    }

    // 当 claim 未被暂停时才允许执行
    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    // 当 withdraw 未被暂停时才允许执行
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    // 初始化函数（可升级合约使用 initialize 代替构造函数）
    function initialize(
        IERC20 _MetaNode,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _MetaNodePerBlock
    ) public initializer {
        // 校验参数：开始区块必须小于等于结束区块且每块奖励必须大于 0
        require(_startBlock <= _endBlock && _MetaNodePerBlock > 0, "invalid parameters");
        // 初始化父类 AccessControl 和 UUPS 可升级逻辑
        __AccessControl_init();
        __UUPSUpgradeable_init();
        // 授予部署者默认管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // 授予部署者升级角色
        _grantRole(UPGRADE_ROLE, msg.sender);
        // 授予部署者自定义管理员角色
        _grantRole(ADMIN_ROLE, msg.sender);
        // 设置 MetaNode 代币合约地址（调用外部函数，要求有 ADMIN_ROLE）
        setMetaNode(_MetaNode);
        // 设置开始块、结束块和每块奖励
        startBlock = _startBlock;
        endBlock = _endBlock;
        MetaNodePerBlock = _MetaNodePerBlock;
    }

    // UUPS 升级授权函数，需要 UPGRADE_ROLE 权限
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADE_ROLE)
        override
    {

    }
    // ************************************** ADMIN FUNCTION **************************************

    // 设置 MetaNode 代币合约地址，只能由具有 ADMIN_ROLE 的账户调用
    function setMetaNode(IERC20 _MetaNode) public onlyRole(ADMIN_ROLE) {
        MetaNode = _MetaNode;
        emit SetMetaNode(MetaNode);
    }

    // 暂停提现功能，只能由 ADMIN_ROLE 调用
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw has been already paused");
        withdrawPaused = true;
        emit PauseWithdraw();
    }

    // 取消暂停提现功能，只能由 ADMIN_ROLE 调用
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw has been already unpaused");
        withdrawPaused = false;
        emit UnpauseWithdraw();
    }

    // 暂停奖励领取功能，只能由 ADMIN_ROLE 调用
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");
        claimPaused = true;
        emit PauseClaim();
    }

    // 取消暂停奖励领取功能，只能由 ADMIN_ROLE 调用
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");
        claimPaused = false;
        emit UnpauseClaim();
    }

    // 设置开始区块，只能由 ADMIN_ROLE 调用
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "start block must be smaller than end block");
        startBlock = _startBlock;
        emit SetStartBlock(_startBlock);
    }

    // 设置结束区块，只能由 ADMIN_ROLE 调用
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(startBlock <= _endBlock, "start block must be smaller than end block");
        endBlock = _endBlock;
        emit SetEndBlock(_endBlock);
    }

    // 设置每块分发的 MetaNode 数量，只能由 ADMIN_ROLE 调用
    function setMetaNodePerBlock(uint256 _MetaNodePerBlock) public onlyRole(ADMIN_ROLE) {
        require(_MetaNodePerBlock > 0, "invalid parameter");
        MetaNodePerBlock = _MetaNodePerBlock;
        emit SetMetaNodePerBlock(_MetaNodePerBlock);
    }

    /**
     * @notice 添加一个新的质押池 只能由 ADMIN_ROLE 调用
     * @param _stTokenAddress 质押代币地址
     *        - ETH池传 `address(0x0)`
     *        - ERC20池传 ERC20 合约地址
     * @param _poolWeight 池子权重，用于按比例分配奖励
     * @param _minDepositAmount 最小质押数量，用户存入时必须 >= 该值
     * @param _unstakeLockedBlocks 解押锁定区块数，用户申请 unstake 后需等待的区块数
     * @param _withUpdate 是否先更新所有池的奖励状态，true 会调用 massUpdatePools()，保证历史奖励计算正确
     */
    function addPool(address _stTokenAddress, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks, bool _withUpdate) public onlyRole(ADMIN_ROLE) {
        // 默认第一个池为 ETH 池，所以第一个池必须使用 address(0x0) 表示 ETH
        if (pool.length > 0) {
            require(_stTokenAddress != address(0x0), "invalid staking token address");
        } else {
            require(_stTokenAddress == address(0x0), "invalid staking token address");
        }
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        require(block.number < endBlock, "Already ended");
        // 如果需要，先更新所有池的状态（可能消耗较多 gas）
        if (_withUpdate) {
            massUpdatePools();
        }
        // 计算该池的初始 lastRewardBlock：如果当前区块已超过 startBlock 则为当前区块，否则为 startBlock
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        // 更新总权重
        totalPoolWeight = totalPoolWeight + _poolWeight;
        // 将新的池加入池数组
        pool.push(Pool({
            stTokenAddress: _stTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accMetaNodePerST: 0,
            stTokenAmount: 0,
            minDepositAmount: _minDepositAmount,
            unstakeLockedBlocks: _unstakeLockedBlocks
        }));

        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    // 更新指定池的最小存入量和解押锁定块数，只能由 ADMIN_ROLE 调用
    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        pool[_pid].minDepositAmount = _minDepositAmount;
        pool[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;
        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    // 设置指定池的权重，只能由 ADMIN_ROLE 调用
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "invalid pool weight");
        if (_withUpdate) {
            massUpdatePools();
        }
        // 调整总权重并更新该池的权重
        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        pool[_pid].poolWeight = _poolWeight;
        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** QUERY FUNCTION **************************************

    // 返回池的数量
    function poolLength() external view returns(uint256) {
        return pool.length;
    }

    // 计算 rewards 的乘数（奖励总量）在给定区块区间 [_from, _to) 之间
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256 multiplier) {
        require(_from <= _to, "invalid block");
        // 如果 _from 早于 startBlock 则修正为 startBlock
        if (_from < startBlock) {_from = startBlock;}
        // 如果 _to 晚于 endBlock 则修正为 endBlock
        if (_to > endBlock) {_to = endBlock;}
        require(_from <= _to, "end block must be greater than start block");
        bool success;
        // 计算区间块数 * 每块奖励，使用 tryMul 捕获溢出
        (success, multiplier) = (_to - _from).tryMul(MetaNodePerBlock);
        require(success, "multiplier overflow");
    }

    // 查询用户在池中的待领取奖励（按当前区块）
    function pendingMetaNode(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return pendingMetaNodeByBlockNumber(_pid, _user, block.number);
    }

    // 按指定区块号计算用户在池中的待领取奖励（用于离线查询历史区块的奖励）
    function pendingMetaNodeByBlockNumber(uint256 _pid, address _user, uint256 _blockNumber) public checkPid(_pid) view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
        uint256 accMetaNodePerST = pool_.accMetaNodePerST;
        uint256 stSupply = pool_.stTokenAmount;
        // 如果查询区块比上次奖励块更新的块数更大，并且池内有抵押，则需计算新增的 accMetaNodePerST
        if (_blockNumber > pool_.lastRewardBlock && stSupply != 0) {
            uint256 multiplier = getMultiplier(pool_.lastRewardBlock, _blockNumber);
            uint256 MetaNodeForPool = multiplier * pool_.poolWeight / totalPoolWeight;
            accMetaNodePerST = accMetaNodePerST + MetaNodeForPool * (1 ether) / stSupply;
        }

        // 用户可领取 = 用户抵押量 * 最新 accMetaNodePerST / 1 ether - 用户已完成计入的奖励 + 用户 pendingMetaNode
        return user_.stAmount * accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;
    }

    // 返回用户在指定池的抵押余额
    function stakingBalance(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return user[_pid][_user].stAmount;
    }

    // 返回用户的解押请求信息：requestAmount（总请求量）和 pendingWithdrawAmount（已解锁可提取量）
    function withdrawAmount(uint256 _pid, address _user) public checkPid(_pid) view returns(uint256 requestAmount, uint256 pendingWithdrawAmount) {
        User storage user_ = user[_pid][_user];
        for (uint256 i = 0; i < user_.requests.length; i++) {
            UnstakeRequest storage req = user_.requests[i];
            requestAmount += req.amount;
            if (req.unlockBlocks <= block.number) {
                pendingWithdrawAmount += req.amount;
            }
        }
        return (requestAmount, pendingWithdrawAmount);
    }

    // ************************************** PUBLIC FUNCTION **************************************

    // 更新某个池的累计奖励变量（accMetaNodePerST）和 lastRewardBlock
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];
        // 如果当前区块小于等于上次记录的 lastRewardBlock，则无需更新
        if (block.number <= pool_.lastRewardBlock) {
            return;
        }
        // 计算从 lastRewardBlock 到当前块之间该池应得的总奖励（先乘以池权重）
        (bool success1, uint256 totalMetaNode) = getMultiplier(pool_.lastRewardBlock, block.number).tryMul(pool_.poolWeight);
        require(success1, "overflow");
        // 按总权重分摊到该池
        (success1, totalMetaNode) = totalMetaNode.tryDiv(totalPoolWeight);
        require(success1, "overflow");
        uint256 stSupply = pool_.stTokenAmount;
        // 如果池中有抵押代币，则更新 accMetaNodePerST
        if (stSupply > 0) {
            (bool success2, uint256 totalMetaNode_) = totalMetaNode.tryMul(1 ether);
            require(success2, "overflow");
            (success2, totalMetaNode_) = totalMetaNode_.tryDiv(stSupply);
            require(success2, "overflow");
            (bool success3, uint256 accMetaNodePerST) = pool_.accMetaNodePerST.tryAdd(totalMetaNode_);
            require(success3, "overflow");
            pool_.accMetaNodePerST = accMetaNodePerST;
        }
        // 更新上次奖励区块为当前区块
        pool_.lastRewardBlock = block.number;
        emit UpdatePool(_pid, pool_.lastRewardBlock, totalMetaNode);
    }

    // 批量更新所有池
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    // 存入 ETH（第 0 个池），payable 函数
    function depositETH() public whenNotPaused() payable {
        Pool storage pool_ = pool[ETH_PID];
        require(pool_.stTokenAddress == address(0x0), "invalid staking token address");
        uint256 _amount = msg.value;
        require(_amount >= pool_.minDepositAmount, "deposit amount is too small");
        _deposit(ETH_PID, _amount);
    }

    // 存入 ERC20 抵押代币到指定池（非 ETH 池）
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) {
        require(_pid != 0, "deposit not support ETH staking");
        Pool storage pool_ = pool[_pid];
        require(_amount > pool_.minDepositAmount, "deposit amount is too small");

        if(_amount > 0) {
            // 使用 safeTransferFrom 从用户转入代币到合约
            IERC20(pool_.stTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }
        _deposit(_pid, _amount);
    }

    // 申请解押（只是把请求写入数组，实际提取需要调用 withdraw）
    function unstake(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        require(user_.stAmount >= _amount, "Not enough staking token balance");

        updatePool(_pid);

        // 计算当前可分配但未结算的奖励
        uint256 pendingMetaNode_ = user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode;

        if(pendingMetaNode_ > 0) {
            user_.pendingMetaNode = user_.pendingMetaNode + pendingMetaNode_;
        }

        if(_amount > 0) {
            // 扣除用户抵押量，并将解押请求加入请求列表，设置 unlockBlocks 为当前块号 + 锁定块数
            user_.stAmount = user_.stAmount - _amount;
            user_.requests.push(UnstakeRequest({
                amount: _amount,
                unlockBlocks: block.number + pool_.unstakeLockedBlocks
            }));
        }
        // 减少池内的抵押总量
        pool_.stTokenAmount = pool_.stTokenAmount - _amount;
        // 更新用户已完成的奖励计数为新的 stAmount 对应的 acc 值
        user_.finishedMetaNode = user_.stAmount * pool_.accMetaNodePerST / (1 ether);
        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    // 提取已解锁的解押金额（遍历用户请求，收集已到期的请求并从请求数组中删除）
    function withdraw(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 pendingWithdraw_;
        uint256 index = 0;
        // 遍历用户解质押请求 解锁区块小于等于当前区块可提现
        while (index < user_.requests.length && user_.requests[index].unlockBlocks <= block.number) {
            pendingWithdraw_ += user_.requests[index].amount;
            index++;
        }
        // 删除已解锁请求
        if (index > 0) {
            for (uint256 i = index; i < user_.requests.length; i++) {
                user_.requests[i - index] = user_.requests[i];
            }
            for (uint256 i = 0; i < index; i++) {
                user_.requests.pop();
            }
        }
        // 实际转账已解锁的金额，如果是 ETH 池则使用 _safeETHTransfer，否则使用 ERC20.safeTransfer
        if (pendingWithdraw_ > 0) {
            if (pool_.stTokenAddress == address(0x0)) {
                _safeETHTransfer(msg.sender, pendingWithdraw_);
            } else {
                IERC20(pool_.stTokenAddress).safeTransfer(msg.sender, pendingWithdraw_);
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }

    // 领取奖励函数：先更新池、计算待发奖励并转账
    function claim(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotClaimPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        updatePool(_pid);

        uint256 pendingMetaNode_ = user_.stAmount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;

        if(pendingMetaNode_ > 0) {
            user_.pendingMetaNode = 0;
            _safeMetaNodeTransfer(msg.sender, pendingMetaNode_);
        }

        user_.finishedMetaNode = user_.stAmount * pool_.accMetaNodePerST / (1 ether);

        emit Claim(msg.sender, _pid, pendingMetaNode_);
    }

    // ************************************** INTERNAL FUNCTION **************************************

    // 内部 deposit 方法：处理用户的奖励结算与状态更新（不负责转账 ERC20/ETH）
    function _deposit(uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];
        updatePool(_pid);
        if (user_.stAmount > 0) {
            (bool success1, uint256 accST) = user_.stAmount.tryMul(pool_.accMetaNodePerST);
            require(success1, "user stAmount mul accMetaNodePerST overflow");
            (success1, accST) = accST.tryDiv(1 ether);
            require(success1, "accST div 1 ether overflow");
            
            (bool success2, uint256 pendingMetaNode_) = accST.trySub(user_.finishedMetaNode);
            require(success2, "accST sub finishedMetaNode overflow");

            if(pendingMetaNode_ > 0) {
                (bool success3, uint256 _pendingMetaNode) = user_.pendingMetaNode.tryAdd(pendingMetaNode_);
                require(success3, "user pendingMetaNode overflow");
                user_.pendingMetaNode = _pendingMetaNode;
            }
        }

        if(_amount > 0) {
            (bool success4, uint256 stAmount) = user_.stAmount.tryAdd(_amount);
            require(success4, "user stAmount overflow");
            user_.stAmount = stAmount;
        }

        (bool success5, uint256 stTokenAmount) = pool_.stTokenAmount.tryAdd(_amount);
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        (bool success6, uint256 finishedMetaNode) = user_.stAmount.tryMul(pool_.accMetaNodePerST);
        require(success6, "user stAmount mul accMetaNodePerST overflow");

        (success6, finishedMetaNode) = finishedMetaNode.tryDiv(1 ether);
        require(success6, "finishedMetaNode div 1 ether overflow");

        user_.finishedMetaNode = finishedMetaNode;

        emit Deposit(msg.sender, _pid, _amount);
    }

    // 安全转账 MetaNode（如果合约余额不足，则转账全部余额）
    function _safeMetaNodeTransfer(address _to, uint256 _amount) internal {
        uint256 MetaNodeBal = MetaNode.balanceOf(address(this));

        if (_amount > MetaNodeBal) {
            MetaNode.transfer(_to, MetaNodeBal);
        } else {
            MetaNode.transfer(_to, _amount);
        }
    }

    // 使用 call 安全地转 ETH 并且检查返回的数据（如果存在的话）
    function _safeETHTransfer(address _to, uint256 _amount) internal {
        (bool success, bytes memory data) = address(_to).call{
            value: _amount
        }("");

        require(success, "ETH transfer call failed");
        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "ETH transfer operation did not succeed"
            );
        }
    }
}