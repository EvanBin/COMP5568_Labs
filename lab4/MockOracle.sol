// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockOracle {
    address public owner;
    uint256 public price; // 1 mETH = price USD, 1e18 精度

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
