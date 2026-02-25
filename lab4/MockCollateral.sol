// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleERC20.sol";

contract MockCollateral is SimpleERC20 {
    constructor() SimpleERC20("Mock ETH", "mETH") {
        // 给部署者一些初始抵押物
        _mint(msg.sender, 1_000_000 ether);
    }

    // 方便助教发币给学生
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
