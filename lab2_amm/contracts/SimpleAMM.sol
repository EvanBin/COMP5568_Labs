// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAMM {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    
    uint256 public reserveA;
    uint256 public reserveB;
    
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;
    
    // Fee: 0.2% (multiply by 998, divide by 1000)
    uint256 public constant FEE_NUMERATOR = 998;
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidityMinted);
    event Swap(address indexed trader, address tokenIn, uint256 amountIn, uint256 amountOut);
    
    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }
    
    // Add liquidity to the pool
    function addLiquidity(uint256 amountA, uint256 amountB) external returns (uint256 liquidityMinted) {
        require(amountA > 0 && amountB > 0, "Amounts must be greater than 0");
        
        // Transfer tokens from user to contract
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        
        // Calculate liquidity shares
        if (totalLiquidity == 0) {
            // First liquidity provider
            liquidityMinted = sqrt(amountA * amountB);
        } else {
            // Subsequent liquidity providers must add proportionally
            uint256 liquidityA = (amountA * totalLiquidity) / reserveA;
            uint256 liquidityB = (amountB * totalLiquidity) / reserveB;
            liquidityMinted = min(liquidityA, liquidityB);
        }
        
        require(liquidityMinted > 0, "Insufficient liquidity minted");
        
        // Update state
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;
        reserveA += amountA;
        reserveB += amountB;
        
        emit LiquidityAdded(msg.sender, amountA, amountB, liquidityMinted);
    }
    
    // Swap Token A for Token B
    function swapAforB(uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be greater than 0");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");
        
        // Calculate output amount with fee
        amountOut = getAmountOut(amountIn, reserveA, reserveB);
        require(amountOut >= minAmountOut, "Slippage too high");
        
        // Transfer tokens
        tokenA.transferFrom(msg.sender, address(this), amountIn);
        tokenB.transfer(msg.sender, amountOut);
        
        // Update reserves
        reserveA += amountIn;
        reserveB -= amountOut;
        
        emit Swap(msg.sender, address(tokenA), amountIn, amountOut);
    }
    
    // Swap Token B for Token A
    function swapBforA(uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be greater than 0");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");
        
        // Calculate output amount with fee
        amountOut = getAmountOut(amountIn, reserveB, reserveA);
        require(amountOut >= minAmountOut, "Slippage too high");
        
        // Transfer tokens
        tokenB.transferFrom(msg.sender, address(this), amountIn);
        tokenA.transfer(msg.sender, amountOut);
        
        // Update reserves
        reserveB += amountIn;
        reserveA -= amountOut;
        
        emit Swap(msg.sender, address(tokenB), amountIn, amountOut);
    }
    
    // Calculate output amount with fee (from lecture slide formula)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) 
        public 
        pure 
        returns (uint256 amountOut) 
    {
        require(amountIn > 0, "Invalid input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient reserves");
        
        // Apply 0.2% fee: amountIn * 998 / 1000
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }
    
    // Calculate required input amount for desired output
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) 
        public 
        pure 
        returns (uint256 amountIn) 
    {
        require(amountOut > 0, "Invalid output amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient reserves");
        require(amountOut < reserveOut, "Insufficient output reserve");
        
        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * FEE_NUMERATOR;
        amountIn = (numerator / denominator) + 1; // +1 for rounding
    }
    
    // Helper: Square root function
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
    
    // Helper: Minimum of two numbers
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }
    
    // View functions
    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }
    
    function getPrice() external view returns (uint256 priceA, uint256 priceB) {
        require(reserveA > 0 && reserveB > 0, "No liquidity");
        // Price of A in terms of B (scaled by 1e18)
        priceA = (reserveB * 1e18) / reserveA;
        // Price of B in terms of A (scaled by 1e18)
        priceB = (reserveA * 1e18) / reserveB;
    }
}
