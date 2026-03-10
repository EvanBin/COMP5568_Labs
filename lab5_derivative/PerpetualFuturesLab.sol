// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simplified Perpetual Futures Exchange Lab

contract PerpetualFuturesExchange {
    address public owner;


    uint256 private price;


    uint256 public totalLiquidity;


    uint256 public constant MAINTENANCE_MARGIN_RATIO = 50; 
    uint256 public constant RATIO_BASE = 100;

    struct Position {
        bool isOpen;
        bool isLong;
        uint256 margin;      
        uint256 size;        
        uint256 entryPrice;  
    }

    mapping(address => Position) public positions;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }


    function setPrice(uint256 _price) external onlyOwner {
        require(_price > 0, "price must be > 0");
        price = _price;
    }


    function getPrice() external view returns (uint256) {
        return price;
    }


    function provideLiquidity() external payable {
        require(msg.value > 0, "No ETH sent");
        totalLiquidity += msg.value;
    }


    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }


    function openLong(uint256 leverage) external payable {
        _openPosition(true, leverage);
    }


    function openShort(uint256 leverage) external payable {
        _openPosition(false, leverage);
    }

    function _openPosition(bool isLong, uint256 leverage) internal {
        require(price > 0, "Price not set");
        require(leverage >= 1 && leverage <= 10, "Leverage out of range");
        require(msg.value > 0, "Margin must be > 0");

        Position storage pos = positions[msg.sender];
        require(!pos.isOpen, "Existing position must be closed first");

        uint256 margin = msg.value;
        uint256 size = margin * leverage; 

        positions[msg.sender] = Position({
            isOpen: true,
            isLong: isLong,
            margin: margin,
            size: size,
            entryPrice: price
        });


        totalLiquidity += margin;
    }


    function getPosition(address trader)
        external
        view
        returns (bool isOpen, bool isLong, uint256 margin, uint256 size, uint256 entryPrice)
    {
        Position memory pos = positions[trader];
        return (pos.isOpen, pos.isLong, pos.margin, pos.size, pos.entryPrice);
    }


    function getPnL(address trader) public view returns (int256) {
        Position memory pos = positions[trader];
        require(pos.isOpen, "No open position");
        require(price > 0, "Price not set");

        // size * (currentPrice - entryPrice) / entryPrice
        if (pos.isLong) {
            int256 diff = int256(price) - int256(pos.entryPrice);
            int256 pnl = int256(pos.size) * diff / int256(pos.entryPrice);
            return pnl;
        } else {
            int256 diff = int256(pos.entryPrice) - int256(price);
            int256 pnl = int256(pos.size) * diff / int256(pos.entryPrice);
            return pnl;
        }
    }


    function isLiquidatable(address trader) public view returns (bool) {
        Position memory pos = positions[trader];
        if (!pos.isOpen) {
            return false;
        }

        int256 pnl = getPnL(trader);

        int256 equity = int256(pos.margin) + pnl;
        if (equity <= 0) {

            return true;
        }


        int256 maintenanceMargin =
            int256(pos.margin) * int256(MAINTENANCE_MARGIN_RATIO) / int256(RATIO_BASE);

        if (equity < maintenanceMargin) {
            return true;
        }
        return false;
    }


    function closePosition() external {
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");

        int256 pnl = getPnL(msg.sender);
        uint256 margin = pos.margin;


        pos.isOpen = false;
        pos.margin = 0;
        pos.size = 0;
        pos.entryPrice = 0;


        int256 payout = int256(margin) + pnl;
        if (payout < 0) {
            payout = 0;
        }



        if (pnl > 0) {

            totalLiquidity -= uint256(pnl);
        } else if (pnl < 0) {

            totalLiquidity += uint256(-pnl);
        }


        if (payout > 0) {
            require(address(this).balance >= uint256(payout), "Insufficient contract balance");
            payable(msg.sender).transfer(uint256(payout));
        }
    }


    function liquidate(address trader) external {
        Position storage pos = positions[trader];
        require(pos.isOpen, "No open position");
        require(isLiquidatable(trader), "Position not liquidatable");

        int256 pnl = getPnL(trader);
        uint256 margin = pos.margin;

        // 清空仓位
        pos.isOpen = false;
        pos.margin = 0;
        pos.size = 0;
        pos.entryPrice = 0;

        int256 equity = int256(margin) + pnl;
        if (equity < 0) {

            equity = 0;
        }


        if (pnl > 0) {
            totalLiquidity -= uint256(pnl);
        } else if (pnl < 0) {
            totalLiquidity += uint256(-pnl);
        }


        if (equity > 0) {
            require(address(this).balance >= uint256(equity), "Insufficient balance");
            payable(trader).transfer(uint256(equity));
        }
    }

    function getTraderEthBalance(address trader) external view returns (uint256) {
    return trader.balance;  
}

}

