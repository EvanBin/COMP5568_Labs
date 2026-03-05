// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleExchange {
    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // --- Liquidity ---
    function addLiquidity(uint256 amountA, uint256 amountB) external {
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        reserveA += amountA;
        reserveB += amountB;
    }

    // --- Swap Token A → Token B ---
    function swapAForB(uint256 amountAIn) external returns (uint256 amountBOut) {
        require(amountAIn > 0, "Amount must be > 0");
        // Constant product: (reserveA + amountAIn) * (reserveB - amountBOut) = reserveA * reserveB
        amountBOut = (reserveB * amountAIn) / (reserveA + amountAIn);
        require(amountBOut > 0 && amountBOut < reserveB, "Insufficient liquidity");

        tokenA.transferFrom(msg.sender, address(this), amountAIn);
        tokenB.transfer(msg.sender, amountBOut);

        reserveA += amountAIn;
        reserveB -= amountBOut;
    }

    // --- Swap Token B → Token A ---
    function swapBForA(uint256 amountBIn) external returns (uint256 amountAOut) {
        require(amountBIn > 0, "Amount must be > 0");
        amountAOut = (reserveA * amountBIn) / (reserveB + amountBIn);
        require(amountAOut > 0 && amountAOut < reserveA, "Insufficient liquidity");

        tokenB.transferFrom(msg.sender, address(this), amountBIn);
        tokenA.transfer(msg.sender, amountAOut);

        reserveB += amountBIn;
        reserveA -= amountAOut;
    }

    // --- Spot-Price Oracle (VULNERABLE!) ---
    // Returns: how many Token B you get per 1 Token A (scaled by 1e18)
    function getSpotPrice() external view returns (uint256) {
        require(reserveA > 0, "No liquidity");
        return (reserveB * 1e18) / reserveA;
    }
}