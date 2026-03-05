// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOracle {
    function getSpotPrice() external view returns (uint256);
}

contract VulnerableLending {
    IERC20 public tokenA;
    IERC20 public tokenB;
    IOracle public oracle;

    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateral required

    mapping(address => uint256) public collateral;  // Token B deposited
    mapping(address => uint256) public debt;         // Token A borrowed

    constructor(address _tokenA, address _tokenB, address _oracle) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        oracle = IOracle(_oracle);
    }

    // Fund the lending pool with Token A
    function fundPool(uint256 amount) external {
        tokenA.transferFrom(msg.sender, address(this), amount);
    }

    // Deposit Token B as collateral
    function depositCollateral(uint256 amount) external {
        tokenB.transferFrom(msg.sender, address(this), amount);
        collateral[msg.sender] += amount;
    }

    // Borrow Token A against deposited collateral
    function borrow(uint256 borrowAmount) external {
        uint256 price = oracle.getSpotPrice(); // <-- VULNERABLE: reads spot price!
        // price = Token B per Token A (scaled 1e18)
        // collateral value in Token A = collateral * 1e18 / price
        uint256 collateralValueInA = (collateral[msg.sender] * 1e18) / price;
        uint256 maxBorrow = (collateralValueInA * 100) / COLLATERAL_RATIO;

        require(borrowAmount <= maxBorrow - debt[msg.sender], "Insufficient collateral");

        debt[msg.sender] += borrowAmount;
        tokenA.transfer(msg.sender, borrowAmount);
    }
}