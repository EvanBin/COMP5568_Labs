// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simplified Perpetual Futures Exchange Lab
/// @notice 教学用简化版永续合约交易所，不可用于生产环境
contract PerpetualFuturesExchange {
    address public owner;

    // 标的资产价格（例如 1 BTC = 2000，单位自定，这里只是纯数字）
    uint256 private price;

    // 流动性池余额（合约持有的总 ETH）
    uint256 public totalLiquidity;

    // 平仓 / 清算时用于判断保证金是否不足
    uint256 public constant MAINTENANCE_MARGIN_RATIO = 50; // 50% (以 1e2 为单位)
    uint256 public constant RATIO_BASE = 100;

    struct Position {
        bool isOpen;
        bool isLong;
        uint256 margin;      // 交易者投入的保证金 (ETH)
        uint256 size;        // 名义头寸大小 = margin * leverage
        uint256 entryPrice;  // 入场价格
    }

    mapping(address => Position) public positions;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Owner 设置标的价格（实验中手动喂价）
    function setPrice(uint256 _price) external onlyOwner {
        require(_price > 0, "price must be > 0");
        price = _price;
    }

    /// @notice 获取当前标的价格
    function getPrice() external view returns (uint256) {
        return price;
    }

    /// @notice 流动性提供者向池子存入 ETH
    function provideLiquidity() external payable {
        require(msg.value > 0, "No ETH sent");
        totalLiquidity += msg.value;
    }

    /// @notice 简单查询合约当前持有 ETH（包括流动性和保证金）
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice 开多头头寸
    /// @param leverage 杠杆倍数，比如 2, 3, 5, 10
    function openLong(uint256 leverage) external payable {
        _openPosition(true, leverage);
    }

    /// @notice 开空头头寸
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
        uint256 size = margin * leverage; // 简化：不做精度处理

        positions[msg.sender] = Position({
            isOpen: true,
            isLong: isLong,
            margin: margin,
            size: size,
            entryPrice: price
        });

        // 保证金也留在合约里，增加 totalLiquidity 概念上是 LP+用户一起承担盈亏
        totalLiquidity += margin;
    }

    /// @notice 查询某账户的头寸信息
    function getPosition(address trader)
        external
        view
        returns (bool isOpen, bool isLong, uint256 margin, uint256 size, uint256 entryPrice)
    {
        Position memory pos = positions[trader];
        return (pos.isOpen, pos.isLong, pos.margin, pos.size, pos.entryPrice);
    }

    /// @notice 计算某交易者的未实现盈亏（PnL），单位为 ETH（简化）
    /// @dev 正数代表盈利，负数代表亏损
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

    /// @notice 判断一个仓位是否应被清算
    /// @dev 简化规则：如果亏损超过 margin 的 (1 - MAINTENANCE_MARGIN_RATIO)，则可清算
    function isLiquidatable(address trader) public view returns (bool) {
        Position memory pos = positions[trader];
        if (!pos.isOpen) {
            return false;
        }

        int256 pnl = getPnL(trader);
        // 当前权益 = margin + pnl
        int256 equity = int256(pos.margin) + pnl;
        if (equity <= 0) {
            // 亏损超过保证金，绝对需要清算
            return true;
        }

        // 维持保证金 = margin * MAINTENANCE_MARGIN_RATIO / RATIO_BASE
        int256 maintenanceMargin =
            int256(pos.margin) * int256(MAINTENANCE_MARGIN_RATIO) / int256(RATIO_BASE);
        // 如果权益低于维持保证金，也应清算
        if (equity < maintenanceMargin) {
            return true;
        }
        return false;
    }

    /// @notice 交易者主动平仓，结算盈亏
    function closePosition() external {
        Position storage pos = positions[msg.sender];
        require(pos.isOpen, "No open position");

        int256 pnl = getPnL(msg.sender);
        uint256 margin = pos.margin;

        // 清空仓位
        pos.isOpen = false;
        pos.margin = 0;
        pos.size = 0;
        pos.entryPrice = 0;

        // 计算应付给用户的金额 = margin + pnl（如果 pnl < 0 则减少）
        int256 payout = int256(margin) + pnl;
        if (payout < 0) {
            payout = 0;
        }

        // 更新 totalLiquidity：合约池的盈亏与用户相反
        // 如果用户盈利(pnl > 0)，池子余额减少；反之增加
        if (pnl > 0) {
            // 用户从池子取钱
            totalLiquidity -= uint256(pnl);
        } else if (pnl < 0) {
            // 用户亏钱，池子增加
            totalLiquidity += uint256(-pnl);
        }

        // 向用户转账
        if (payout > 0) {
            require(address(this).balance >= uint256(payout), "Insufficient contract balance");
            payable(msg.sender).transfer(uint256(payout));
        }
    }

    /// @notice 任意人均可触发对某个可被清算的仓位进行清算
    /// @dev 教学简化：清算者不拿奖励，所有剩余价值退给原交易者
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
            // 用户的保证金全部亏完，池子已经吸收了损失
            equity = 0;
        }

        // 更新池子余额：同 closePosition
        if (pnl > 0) {
            totalLiquidity -= uint256(pnl);
        } else if (pnl < 0) {
            totalLiquidity += uint256(-pnl);
        }

        // 把剩余的 equity（如果有）退给被清算的用户
        if (equity > 0) {
            require(address(this).balance >= uint256(equity), "Insufficient balance");
            payable(trader).transfer(uint256(equity));
        }
    }
    //查看账户余额
    function getTraderEthBalance(address trader) external view returns (uint256) {
    return trader.balance;  // 返回单位是 wei
}

}
