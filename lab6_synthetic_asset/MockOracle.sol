// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Mock ETH/USD Price Oracle
/// @notice Simple mock oracle returning ETH price in USD with 8 decimals
contract MockOracle {
    // price with 8 decimals, e.g. 2000 * 1e8 = 200000000000
    int256 private price;

    address public owner;

    event PriceUpdated(int256 newPrice);

    constructor(int256 _initialPrice) {
        owner = msg.sender;
        price = _initialPrice;
        emit PriceUpdated(_initialPrice);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Returns latest ETH/USD price, 8 decimals
    function latestAnswer() external view returns (int256) {
        return price;
    }

    /// @notice Update ETH/USD price manually
    function setPrice(int256 _newPrice) external onlyOwner {
        require(_newPrice > 0, "Price must be positive");
        price = _newPrice;
        emit PriceUpdated(_newPrice);
    }
}
