// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceOracle {
    function latestAnswer() external view returns (int256);
}

/// @title Risk Sharing Synthetic Asset System
/// @notice ETH-collateral, sUSD + sBTC, with global debt pool & risk sharing
contract RiskSharingSynth {
    // ---------- ERC20-like data for sUSD & sBTC ----------
    string public constant sUSD_NAME = "Synthetic USD";
    string public constant sUSD_SYMBOL = "sUSD";
    string public constant sBTC_NAME = "Synthetic BTC";
    string public constant sBTC_SYMBOL = "sBTC";

    uint8 public constant DECIMALS = 18; // for both tokens

    // sUSD balances
    mapping(address => uint256) public sUSDBalance;
    uint256 public totalSupplySUSD;

    // sBTC balances (amount in BTC, 18 decimals)
    mapping(address => uint256) public sBTCBalance;
    uint256 public totalSupplySBTC;

    event TransferSUSD(address indexed from, address indexed to, uint256 value);
    event TransferSBTC(address indexed from, address indexed to, uint256 value);

    // ---------- Collateral & Debt Pool ----------

    mapping(address => uint256) public collateralETH;

    uint256 public totalDebtUSD;

    uint256 public totalDebtShares;
    mapping(address => uint256) public debtShares;

    uint256 public collateralRatioBps = 15000;


    IPriceOracle public ethOracle;
    IPriceOracle public btcOracle;

    int256 public constant ORACLE_DECIMALS = 1e8;

    event CollateralDeposited(address indexed user, uint256 amountETH);
    event CollateralWithdrawn(address indexed user, uint256 amountETH);
    event MintedSUSD(address indexed user, uint256 amountSUSD, uint256 debtValueUSD);
    event MintedSBTC(address indexed user, uint256 amountSBTC, uint256 debtValueUSD);
    event BurnedSUSD(address indexed user, uint256 amountSUSD, uint256 debtValueUSD);
    event BurnedSBTC(address indexed user, uint256 amountSBTC, uint256 debtValueUSD);

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


        _increaseDebt(msg.sender, _amountSUSD);


        require(_isAccountSafe(msg.sender), "Not enough collateral");


        sUSDBalance[msg.sender] += _amountSUSD;
        totalSupplySUSD += _amountSUSD;

        emit MintedSUSD(msg.sender, _amountSUSD, _amountSUSD);
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

        _decreaseDebt(msg.sender, repayAmountUSD);

  
        sUSDBalance[msg.sender] -= repayAmountUSD;
        totalSupplySUSD -= repayAmountUSD;

        emit BurnedSUSD(msg.sender, repayAmountUSD, repayAmountUSD);
    }

    // ---------- Mint / Burn sBTC ----------


    function mintSBTC(uint256 _amountSBTC) external {
        require(_amountSBTC > 0, "Zero mint");

        uint256 btcPrice = getBTCPrice(); // 8 decimals

        // _amountSBTC(1e18) * btcPrice(1e8) / 1e8 => 1e18
        uint256 debtValueUSD = _amountSBTC * btcPrice / uint256(ORACLE_DECIMALS);

        _increaseDebt(msg.sender, debtValueUSD);
        require(_isAccountSafe(msg.sender), "Not enough collateral");

        sBTCBalance[msg.sender] += _amountSBTC;
        totalSupplySBTC += _amountSBTC;

        emit MintedSBTC(msg.sender, _amountSBTC, debtValueUSD);
    }


    function burnSBTC(uint256 _amountSBTC) external {
        require(_amountSBTC > 0, "Zero burn");
        require(sBTCBalance[msg.sender] >= _amountSBTC, "Not enough sBTC");

        uint256 btcPrice = getBTCPrice();
        uint256 repayValueUSD = _amountSBTC * btcPrice / uint256(ORACLE_DECIMALS);

        uint256 userDebt = getUserDebtUSD(msg.sender);
        require(userDebt > 0, "No debt");

        if (repayValueUSD > userDebt) {
            repayValueUSD = userDebt;

        }

        _decreaseDebt(msg.sender, repayValueUSD);


        sBTCBalance[msg.sender] -= _amountSBTC;
        totalSupplySBTC -= _amountSBTC;

        emit BurnedSBTC(msg.sender, _amountSBTC, repayValueUSD);
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

    function _increaseDebt(address _user, uint256 _debtUSD) internal {
        if (totalDebtUSD == 0 || totalDebtShares == 0) {

            debtShares[_user] += _debtUSD;
            totalDebtShares += _debtUSD;
        } else {

            // shares = _debtUSD * totalDebtShares / totalDebtUSD
            uint256 newShares = _debtUSD * totalDebtShares / totalDebtUSD;
            require(newShares > 0, "Too small debt");
            debtShares[_user] += newShares;
            totalDebtShares += newShares;
        }
        totalDebtUSD += _debtUSD;
    }


    function _decreaseDebt(address _user, uint256 _repayUSD) internal {
        uint256 userShares = debtShares[_user];
        require(userShares > 0, "No debt shares");

        uint256 userDebt = getUserDebtUSD(_user);
        if (_repayUSD > userDebt) {
            _repayUSD = userDebt;
        }


        uint256 shareToBurn = userShares * _repayUSD / userDebt;
        if (shareToBurn > userShares) {
            shareToBurn = userShares;
        }

        debtShares[_user] -= shareToBurn;
        totalDebtShares -= shareToBurn;
        totalDebtUSD -= _repayUSD;
    }


    function getUserDebtUSD(address _user) public view returns (uint256) {
        if (totalDebtShares == 0) return 0;
        uint256 shares = debtShares[_user];
        if (shares == 0) return 0;
        return totalDebtUSD * shares / totalDebtShares;
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
        debtUSD = getUserDebtUSD(_user);

        uint256 ethPrice = getETHPrice();
        // ETH(wei) * price(1e8) / 1e18 => USD(1e8)

        uint256 usdValueRaw = collateralETHAmount * ethPrice / 1e18; // 结果 1e8
        collateralUSDValue = usdValueRaw * 1e10; // 1e18

        if (debtUSD == 0) {
            currentCollateralRatioBps = type(uint256).max;
        } else {
            currentCollateralRatioBps = collateralUSDValue * 10000 / debtUSD;
        }
    }


    function getMaxAdditionalDebtUSD(address _user) external view returns (uint256) {
        (, uint256 collateralUSDValue, uint256 debtUSD, ) = this.getAccountInfo(_user);
        if (collateralUSDValue == 0) return 0;
        uint256 maxDebt = collateralUSDValue * 10000 / collateralRatioBps;
        if (maxDebt <= debtUSD) return 0;
        return maxDebt - debtUSD;
    }

    // ---------- Internal helpers ----------

    function _isAccountSafe(address _user) internal view returns (bool) {
        (, uint256 collateralUSDValue, uint256 debtUSD, ) = this.getAccountInfo(_user);
        if (debtUSD == 0) return true;
        uint256 ratio = collateralUSDValue * 10000 / debtUSD;
        return ratio >= collateralRatioBps;
    }
}
