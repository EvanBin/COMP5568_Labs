// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockCollateral.sol";
import "./Stablecoin.sol";
import "./MockOracle.sol";

contract VaultEngine {
    MockCollateral public collateralToken;
    Stablecoin public stablecoin;
    MockOracle public oracle;


    uint256 public collateralFactor;      
    uint256 public liquidationThreshold;  
    uint256 public liquidationPenalty;   

    struct Position {
        uint256 collateral; 
        uint256 debt;       
    }

    mapping(address => Position) public positions;


    uint256 private _locked;
    modifier nonReentrant() {
        require(_locked == 0, "reentrancy");
        _locked = 1;
        _;
        _locked = 0;
    }

    constructor(
        address _collateral,
        address _stablecoin,
        address _oracle,
        uint256 _collateralFactor,
        uint256 _liquidationThreshold,
        uint256 _liquidationPenalty
    ) {
        collateralToken = MockCollateral(_collateral);
        stablecoin = Stablecoin(_stablecoin);
        oracle = MockOracle(_oracle);
        collateralFactor = _collateralFactor;
        liquidationThreshold = _liquidationThreshold;
        liquidationPenalty = _liquidationPenalty;
    }



    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount = 0");
        collateralToken.transferFrom(msg.sender, address(this), amount);
        positions[msg.sender].collateral += amount;
    }

    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "amount = 0");
        Position storage p = positions[msg.sender];

        uint256 newDebt = p.debt + amount;
        require(_isHealthy(p.collateral, newDebt, collateralFactor), "borrow: undercollateralized");

        p.debt = newDebt;
        stablecoin.mint(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        Position storage p = positions[msg.sender];
        require(amount > 0, "amount = 0");
        require(p.debt >= amount, "repay too much");

        stablecoin.transferFrom(msg.sender, address(this), amount);
        stablecoin.burn(address(this), amount);
        p.debt -= amount;
    }

    function withdraw(uint256 amount) external nonReentrant {
        Position storage p = positions[msg.sender];
        require(amount > 0, "amount = 0");
        require(p.collateral >= amount, "insufficient collateral");

        uint256 newCollateral = p.collateral - amount;
        require(_isHealthy(newCollateral, p.debt, collateralFactor), "withdraw: unsafe");

        p.collateral = newCollateral;
        collateralToken.transfer(msg.sender, amount);
    }



    function liquidate(address user) external nonReentrant {
        Position storage p = positions[user];
        require(p.debt > 0, "no debt");


        require(!_isHealthy(p.collateral, p.debt, liquidationThreshold), "position healthy");

        uint256 debt = p.debt;


        stablecoin.transferFrom(msg.sender, address(this), debt);
        stablecoin.burn(address(this), debt);


        uint256 collateralNeeded = _debtToCollateral(debt);
        uint256 collateralToSeize = collateralNeeded * liquidationPenalty / 1e18;

        if (collateralToSeize > p.collateral) {
            collateralToSeize = p.collateral;
        }

        p.debt = 0;
        p.collateral -= collateralToSeize;

        collateralToken.transfer(msg.sender, collateralToSeize);
    }



    function _isHealthy(
        uint256 collateral,
        uint256 debt,
        uint256 factor
    ) internal view returns (bool) {
        if (debt == 0) return true;

        uint256 price = oracle.price(); // 1 mETH = price USD (1e18)
        if (price == 0) return false;


        uint256 collateralValue = collateral * price / 1e18;

        uint256 requiredCollateralValue = debt * factor / 1e18;

        return collateralValue >= requiredCollateralValue;
    }

    function _debtToCollateral(uint256 debt) internal view returns (uint256) {
        uint256 price = oracle.price();
        require(price > 0, "price = 0");
        // debt(USD) / price(USD per mETH) = mETH 
        return debt * 1e18 / price;
    }
}

