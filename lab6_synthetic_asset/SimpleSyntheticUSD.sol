// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceOracle {
    function latestAnswer() external view returns (int256);
}

/// @title Simple Synthetic USD backed by ETH
/// @notice Over-collateralized sUSD using ETH as collateral and a mock oracle
contract SimpleSyntheticUSD {
    // ---------- ERC20 basic data ----------
    string public name = "Synthetic USD";
    string public symbol = "sUSD";
    uint8 public decimals = 18;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ---------- Collateral & Debt data ----------
    IPriceOracle public oracle;

    // The amount of ETH (in wei) that the user has mortgaged
    mapping(address => uint256) public collateralETH;

    // The current sUSD debt of the user (the amount of sUSD that has been minted)
    mapping(address => uint256) public debtSUSD;

    // Collateral ratio, for example 150% => 15000, indicating 150%, with two decimal places added for easier adjustment
    // During actual calculation, it will be divided by 1000
    uint256 public collateralRatio = 15000; // 150%

    // Price decimal places (consistent with Oracle)
    int256 public constant ORACLE_DECIMALS = 1e8;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event CollateralDeposited(address indexed user, uint256 amountETH);
    event CollateralWithdrawn(address indexed user, uint256 amountETH);
    event Minted(address indexed user, uint256 amountSUSD);
    event Burned(address indexed user, uint256 amountSUSD);

    constructor(address _oracle) {
        oracle = IPriceOracle(_oracle);
    }

    // ---------- Internal ERC20 helper ----------
    function _transfer(address _from, address _to, uint256 _value) internal {
        require(balanceOf[_from] >= _value, "Insufficient balance");
        unchecked {
            balanceOf[_from] -= _value;
            balanceOf[_to] += _value;
        }
        emit Transfer(_from, _to, _value);
    }

    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) external returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        uint256 allowed = allowance[_from][msg.sender];
        require(allowed >= _value, "Allowance exceeded");
        if (allowed != type(uint256).max) {
            allowance[_from][msg.sender] = allowed - _value;
        }
        _transfer(_from, _to, _value);
        return true;
    }

    // ---------- Core logic: Collateral & Mint/Burn ----------

    /// @notice Deposit ETH as collateral
    function depositCollateral() external payable {
        require(msg.value > 0, "No ETH sent");
        collateralETH[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    /// @notice Extract a portion of ETH collateral
    /// @dev Ensure that the account still meets the collateralization rate requirement after the extraction
    function withdrawCollateral(uint256 _amountWei) external {
        require(collateralETH[msg.sender] >= _amountWei, "Insufficient collateral");
        // Before extraction, temporarily disable it and check the collateralization rate.
        collateralETH[msg.sender] -= _amountWei;

        // If the user still has debts, it is necessary to check whether the collateralization rate remains safe after the withdrawal.
        if (debtSUSD[msg.sender] > 0) {
            require(_isAccountSafe(msg.sender), "Account would be undercollateralized");
        }

        // Transfer ETH via call
        (bool success, ) = msg.sender.call{value: _amountWei}("");
        require(success, "ETH transfer failed");
        emit CollateralWithdrawn(msg.sender, _amountWei);
    }

    /// @notice Use the existing ETH to mint sUSD
    function mint(uint256 _amountSUSD) external {
        require(_amountSUSD > 0, "Zero mint");

        // Increase user debt
        debtSUSD[msg.sender] += _amountSUSD;
        // At the same time, issue sUSD tokens to the users
        totalSupply += _amountSUSD;
        balanceOf[msg.sender] += _amountSUSD;
        emit Minted(msg.sender, _amountSUSD);
        emit Transfer(address(0), msg.sender, _amountSUSD);

        // Check whether the user account is within the safe collateralization rate range.
        require(_isAccountSafe(msg.sender), "Not enough collateral");
    }

    /// @notice Return sUSD, destroy the tokens, and retrieve ETH in proportion.
    /// @dev When returning the money, it is not mandatory to pay it all at once. Partial repayment is also allowed.
    function burn(uint256 _amountSUSD) external {
        require(_amountSUSD > 0, "Zero burn");
        require(balanceOf[msg.sender] >= _amountSUSD, "Not enough sUSD balance");
        require(debtSUSD[msg.sender] >= _amountSUSD, "Debt less than amount");

        // Destroy sUSD
        balanceOf[msg.sender] -= _amountSUSD;
        totalSupply -= _amountSUSD;
        debtSUSD[msg.sender] -= _amountSUSD;
        emit Burned(msg.sender, _amountSUSD);
        emit Transfer(msg.sender, address(0), _amountSUSD);

        // Here, ETH will not be automatically returned. Users need to withdrawCollateral themselves to obtain it.
    }

    // ---------- View Functions ----------

    /// @notice Return the value (in USD) of the ETH that the user has mortgaged and the current debt.
    function getAccountInfo(address _user) external view returns (
        uint256 collateralETHAmount,
        uint256 collateralUSDValue,
        uint256 debt,
        uint256 currentCollateralRatioBps
    ) {
        collateralETHAmount = collateralETH[_user];
        debt = debtSUSD[_user];

        uint256 price = _getETHPrice(); // 8 decimals
        // ETH (wei) -> ETH -> USD:
        // collateralETHAmount (wei) * price / 1e18
        uint256 usdValue = collateralETHAmount * price / 1e18;
        collateralUSDValue = usdValue;

        if (debt == 0) {
            currentCollateralRatioBps = type(uint256).max; // When there is no debt, it is considered to be infinitely large.
        } else {
            // collateralRatio = collateralUSDValue / debt
            // 再换成 bps（*10000）
            currentCollateralRatioBps = usdValue * 10000 / debt;
        }
    }

    /// @notice Calculate how many more sUSD a certain user can mint at most.
    function getMaxMintableSUSD(address _user) external view returns (uint256) {
        uint256 price = _getETHPrice();
        uint256 usdValue = collateralETH[_user] * price / 1e18;
        // Maximum debt = collateralUSDValue / (collateralRatio / 10000)
        uint256 maxDebt = usdValue * 10000 / collateralRatio;

        if (maxDebt <= debtSUSD[_user]) {
            return 0;
        } else {
            return maxDebt - debtSUSD[_user];
        }
    }

    // ---------- Internal helpers ----------

    /// @dev Read the ETH/USD price (positive value) from Oracle
    function _getETHPrice() internal view returns (uint256) {
        int256 answer = oracle.latestAnswer();
        require(answer > 0, "Invalid oracle price");
        return uint256(answer); // 8 decimals
    }

    /// @dev Check whether the current collateralization status of the user is safe (the collateralization rate is greater than or equal to the set collateralization rate)
    function _isAccountSafe(address _user) internal view returns (bool) {
        uint256 debt = debtSUSD[_user];
        if (debt == 0) {
            return true; // There is no debt, and there is always safety.
        }
        uint256 price = _getETHPrice();
        uint256 usdValue = collateralETH[_user] * price / 1e18;

        // Current pledge rate (bps) = collateralUSDValue / debt * 1000
        uint256 currentRatio = usdValue * 10000 / debt;
        return currentRatio >= collateralRatio;
    }
}
