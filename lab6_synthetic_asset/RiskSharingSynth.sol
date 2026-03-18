// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceOracle {
    function latestAnswer() external view returns (int256);
}

/// @title Risk Sharing Synthetic Asset System (Dynamic Debt Pool Version)
/// @notice ETH-collateral, sUSD + sBTC, with global debt pool & risk sharing
/// @dev Core fix: total system debt is marked to market using current oracle prices.
contract RiskSharingSynth {
    // ---------- ERC20-like data for sUSD & sBTC ----------
    string public constant sUSD_NAME = "Synthetic USD";
    string public constant sUSD_SYMBOL = "sUSD";
    string public constant sBTC_NAME = "Synthetic BTC";
    string public constant sBTC_SYMBOL = "sBTC";

    uint8 public constant DECIMALS = 18; // for both tokens
    uint256 public constant ORACLE_DECIMALS = 1e8;

    // sUSD balances (1 sUSD = 1 USD, 18 decimals)
    mapping(address => uint256) public sUSDBalance;
    uint256 public totalSupplySUSD;

    // sBTC balances (amount in BTC, 18 decimals)
    mapping(address => uint256) public sBTCBalance;
    uint256 public totalSupplySBTC;

    event TransferSUSD(address indexed from, address indexed to, uint256 value);
    event TransferSBTC(address indexed from, address indexed to, uint256 value);

    // ---------- Collateral & Debt Shares ----------
    mapping(address => uint256) public collateralETH;

    // Users do not hold fixed debt amounts; they hold shares of the global debt pool.
    uint256 public totalDebtShares;
    mapping(address => uint256) public debtShares;

    // 15000 bps = 150%
    uint256 public collateralRatioBps = 15000;

    IPriceOracle public ethOracle;
    IPriceOracle public btcOracle;

    event CollateralDeposited(address indexed user, uint256 amountETH);
    event CollateralWithdrawn(address indexed user, uint256 amountETH);
    event MintedSUSD(address indexed user, uint256 amountSUSD, uint256 debtValueUSD, uint256 sharesIssued);
    event MintedSBTC(address indexed user, uint256 amountSBTC, uint256 debtValueUSD, uint256 sharesIssued);
    event BurnedSUSD(address indexed user, uint256 amountSUSD, uint256 debtValueUSD, uint256 sharesBurned);
    event BurnedSBTC(address indexed user, uint256 amountSBTC, uint256 debtValueUSD, uint256 sharesBurned);

    constructor(address _ethOracle, address _btcOracle) {
        ethOracle = IPriceOracle(_ethOracle);
        btcOracle = IPriceOracle(_btcOracle);
    }

    // ---------- Collateral ----------

    function depositCollateral() external payable {
        require(msg.value > 0, "No ETH sent");
        collateralETH[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 _amountWei) external {
        require(collateralETH[msg.sender] >= _amountWei, "Insufficient collateral");

        collateralETH[msg.sender] -= _amountWei;
        require(_isAccountSafe(msg.sender), "Undercollateralized after withdraw");

        (bool success, ) = msg.sender.call{value: _amountWei}("");
        require(success, "ETH transfer failed");
        emit CollateralWithdrawn(msg.sender, _amountWei);
    }

    // ---------- Mint / Burn sUSD ----------

    function mintSUSD(uint256 _amountSUSD) external {
        require(_amountSUSD > 0, "Zero mint");

        uint256 sharesIssued = _issueDebtShares(msg.sender, _amountSUSD);

        sUSDBalance[msg.sender] += _amountSUSD;
        totalSupplySUSD += _amountSUSD;

        require(_isAccountSafe(msg.sender), "Not enough collateral");

        emit MintedSUSD(msg.sender, _amountSUSD, _amountSUSD, sharesIssued);
    }

    function burnSUSD(uint256 _amountSUSD) external {
        require(_amountSUSD > 0, "Zero burn");
        require(sUSDBalance[msg.sender] >= _amountSUSD, "Not enough sUSD");

        uint256 userDebt = getUserDebtUSD(msg.sender);
        require(userDebt > 0, "No debt");

        uint256 repayAmountUSD = _amountSUSD;
        if (repayAmountUSD > userDebt) {
            repayAmountUSD = userDebt;
        }

        uint256 sharesBurned = _burnDebtShares(msg.sender, repayAmountUSD);

        sUSDBalance[msg.sender] -= repayAmountUSD;
        totalSupplySUSD -= repayAmountUSD;

        emit BurnedSUSD(msg.sender, repayAmountUSD, repayAmountUSD, sharesBurned);
    }

    // ---------- Mint / Burn sBTC ----------

    function mintSBTC(uint256 _amountSBTC) external {
        require(_amountSBTC > 0, "Zero mint");

        uint256 btcPrice = getBTCPrice(); // 8 decimals
        uint256 debtValueUSD = (_amountSBTC * btcPrice) / ORACLE_DECIMALS; // 18 decimals

        uint256 sharesIssued = _issueDebtShares(msg.sender, debtValueUSD);

        sBTCBalance[msg.sender] += _amountSBTC;
        totalSupplySBTC += _amountSBTC;

        require(_isAccountSafe(msg.sender), "Not enough collateral");

        emit MintedSBTC(msg.sender, _amountSBTC, debtValueUSD, sharesIssued);
    }

    function burnSBTC(uint256 _amountSBTC) external {
        require(_amountSBTC > 0, "Zero burn");
        require(sBTCBalance[msg.sender] >= _amountSBTC, "Not enough sBTC");

        uint256 userDebt = getUserDebtUSD(msg.sender);
        require(userDebt > 0, "No debt");

        uint256 btcPrice = getBTCPrice();
        uint256 requestedRepayValueUSD = (_amountSBTC * btcPrice) / ORACLE_DECIMALS;

        uint256 actualBurnAmountSBTC = _amountSBTC;
        uint256 actualRepayValueUSD = requestedRepayValueUSD;

        // Do not allow repaying more debt than the user currently owes.
        if (actualRepayValueUSD > userDebt) {
            actualBurnAmountSBTC = (userDebt * ORACLE_DECIMALS) / btcPrice;
            require(actualBurnAmountSBTC > 0, "Burn amount too small");
            actualRepayValueUSD = (actualBurnAmountSBTC * btcPrice) / ORACLE_DECIMALS;
        }

        uint256 sharesBurned = _burnDebtShares(msg.sender, actualRepayValueUSD);

        sBTCBalance[msg.sender] -= actualBurnAmountSBTC;
        totalSupplySBTC -= actualBurnAmountSBTC;

        emit BurnedSBTC(msg.sender, actualBurnAmountSBTC, actualRepayValueUSD, sharesBurned);
    }

    // ---------- Token Transfers (simple) ----------

    function transferSUSD(address _to, uint256 _amount) external returns (bool) {
        require(sUSDBalance[msg.sender] >= _amount, "Insufficient sUSD");
        sUSDBalance[msg.sender] -= _amount;
        sUSDBalance[_to] += _amount;
        emit TransferSUSD(msg.sender, _to, _amount);
        return true;
    }

    function transferSBTC(address _to, uint256 _amount) external returns (bool) {
        require(sBTCBalance[msg.sender] >= _amount, "Insufficient sBTC");
        sBTCBalance[msg.sender] -= _amount;
        sBTCBalance[_to] += _amount;
        emit TransferSBTC(msg.sender, _to, _amount);
        return true;
    }

    // ---------- Debt Pool (Risk Sharing) ----------

    /// @notice Issue debt shares according to current global debt pool value before minting new synths.
    function _issueDebtShares(address _user, uint256 _debtUSD) internal returns (uint256 newShares) {
        uint256 currentDebt = getCurrentTotalDebtUSD();

        if (currentDebt == 0 || totalDebtShares == 0) {
            newShares = _debtUSD;
        } else {
            newShares = (_debtUSD * totalDebtShares) / currentDebt;
            require(newShares > 0, "Too small debt");
        }

        debtShares[_user] += newShares;
        totalDebtShares += newShares;
    }

    /// @notice Burn debt shares in proportion to the user's current debt.
    function _burnDebtShares(address _user, uint256 _repayUSD) internal returns (uint256 shareToBurn) {
        uint256 userShares = debtShares[_user];
        require(userShares > 0, "No debt shares");

        uint256 userDebt = getUserDebtUSD(_user);
        require(userDebt > 0, "No debt");

        if (_repayUSD > userDebt) {
            _repayUSD = userDebt;
        }

        shareToBurn = (userShares * _repayUSD) / userDebt;
        if (shareToBurn == 0 && _repayUSD > 0) {
            shareToBurn = 1;
        }
        if (shareToBurn > userShares) {
            shareToBurn = userShares;
        }

        debtShares[_user] -= shareToBurn;
        totalDebtShares -= shareToBurn;
    }

    /// @notice Current total system debt, marked to market using current oracle prices.
    /// @dev sUSD is always 1 USD; sBTC is valued using current BTC/USD oracle.
    function getCurrentTotalDebtUSD() public view returns (uint256) {
        uint256 btcDebtUSD = (totalSupplySBTC * getBTCPrice()) / ORACLE_DECIMALS;
        return totalSupplySUSD + btcDebtUSD;
    }

    /// @notice User's current debt = current total debt * user's debt share ratio.
    function getUserDebtUSD(address _user) public view returns (uint256) {
        if (totalDebtShares == 0) return 0;

        uint256 shares = debtShares[_user];
        if (shares == 0) return 0;

        uint256 currentTotalDebt = getCurrentTotalDebtUSD();
        if (currentTotalDebt == 0) return 0;

        return (currentTotalDebt * shares) / totalDebtShares;
    }

    // ---------- View Functions ----------

    function getETHPrice() public view returns (uint256) {
        int256 answer = ethOracle.latestAnswer();
        require(answer > 0, "Invalid ETH price");
        return uint256(answer); // 8 decimals
    }

    function getBTCPrice() public view returns (uint256) {
        int256 answer = btcOracle.latestAnswer();
        require(answer > 0, "Invalid BTC price");
        return uint256(answer); // 8 decimals
    }

    function getCollateralUSDValue(address _user) public view returns (uint256) {
        uint256 ethPrice = getETHPrice(); // 8 decimals
        uint256 usdValueRaw = (collateralETH[_user] * ethPrice) / 1e18; // 8 decimals
        return usdValueRaw * 1e10; // convert to 18 decimals
    }

    function getAccountInfo(address _user)
        external
        view
        returns (
            uint256 collateralETHAmount,
            uint256 collateralUSDValue,
            uint256 debtUSD,
            uint256 currentCollateralRatioBps
        )
    {
        collateralETHAmount = collateralETH[_user];
        collateralUSDValue = getCollateralUSDValue(_user);
        debtUSD = getUserDebtUSD(_user);

        if (debtUSD == 0) {
            currentCollateralRatioBps = type(uint256).max;
        } else {
            currentCollateralRatioBps = (collateralUSDValue * 10000) / debtUSD;
        }
    }

    function getMaxAdditionalDebtUSD(address _user) external view returns (uint256) {
        uint256 collateralUSDValue = getCollateralUSDValue(_user);
        uint256 debtUSD = getUserDebtUSD(_user);

        if (collateralUSDValue == 0) return 0;

        uint256 maxDebt = (collateralUSDValue * 10000) / collateralRatioBps;
        if (maxDebt <= debtUSD) return 0;

        return maxDebt - debtUSD;
    }

    // ---------- Internal helper ----------

    function _isAccountSafe(address _user) internal view returns (bool) {
        uint256 debtUSD = getUserDebtUSD(_user);
        if (debtUSD == 0) return true;

        uint256 collateralUSDValue = getCollateralUSDValue(_user);
        uint256 ratio = (collateralUSDValue * 10000) / debtUSD;
        return ratio >= collateralRatioBps;
    }
}
