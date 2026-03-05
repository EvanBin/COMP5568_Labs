// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleERC20.sol";

contract Stablecoin is SimpleERC20 {
    address public owner;
    address public minter; // VaultEngine

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "not minter");
        _;
    }

    constructor() SimpleERC20("Course Stablecoin", "cUSD") {
        owner = msg.sender;
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
