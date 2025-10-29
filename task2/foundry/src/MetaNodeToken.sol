// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MetaNodeToken is ERC20, Ownable {
 
    /// @param initialSupply 初始发行量（单位：wei）
    constructor(uint256 initialSupply)
        ERC20("MetaNodeToken", "MND") 
        Ownable(msg.sender)            
    {
        // 铸造初始代币给部署者（即 owner）
        _mint(msg.sender, initialSupply);
    }

    // -------------------------------
    // 🔹 仅管理员可调用的增发函数
    // -------------------------------
    /// @notice 管理员可增发新代币（例如补充奖励池）
    /// @param to 接收新增代币的地址
    /// @param amount 新增数量（单位：wei）
    function mint(address to, uint256 amount) external onlyOwner {
        // 调用 ERC20 内部方法 _mint() 增发代币
        _mint(to, amount);
    }
}