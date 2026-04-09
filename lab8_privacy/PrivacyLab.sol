// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


contract TraceablePayments {
    event DirectPayment(
        address indexed from,
        address indexed to,
        uint256 amount,
        string memo
    );

    function pay(address payable recipient, string calldata memo) external payable {
        require(msg.value > 0, "Must send ETH");
        recipient.transfer(msg.value);
        emit DirectPayment(msg.sender, recipient, msg.value, memo);
    }

    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract ClassroomMixer {
    uint256 public immutable denomination;
    address public owner;

    uint256 public depositCount;
    uint256 public payoutCount;
    uint256 public batchCount;

    struct DepositRecord {
        address depositor;
        uint256 amount;
        uint256 timestamp;
        uint256 batchHint; 
    }

    struct PayoutRecord {
        address recipient;
        uint256 amount;
        uint256 timestamp;
        uint256 batchId;
    }

    DepositRecord[] public deposits;
    PayoutRecord[] public payouts;

    event Deposited(
        uint256 indexed depositId,
        address indexed depositor,
        uint256 amount,
        uint256 timestamp
    );

    event BatchPaidOut(
        uint256 indexed batchId,
        uint256 recipientCount,
        uint256 amountPerRecipient,
        uint256 timestamp
    );

    event PaidRecipient(
        uint256 indexed batchId,
        uint256 indexed payoutId,
        address indexed recipient,
        uint256 amount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _denominationWei) {
        require(_denominationWei > 0, "Invalid denomination");
        owner = msg.sender;
        denomination = _denominationWei;
    }

    function deposit() external payable {
        require(msg.value == denomination, "Must deposit exact denomination");

        deposits.push(
            DepositRecord({
                depositor: msg.sender,
                amount: msg.value,
                timestamp: block.timestamp,
                batchHint: batchCount + 1
            })
        );

        emit Deposited(depositCount, msg.sender, msg.value, block.timestamp);
        depositCount += 1;
    }


    function batchPayout(address payable[] calldata recipients) external onlyOwner {
        require(recipients.length > 0, "Empty recipients");

        uint256 required = recipients.length * denomination;
        require(address(this).balance >= required, "Insufficient mixer balance");

        uint256 currentBatchId = batchCount;

        for (uint256 i = 0; i < recipients.length; i++) {
            recipients[i].transfer(denomination);

            payouts.push(
                PayoutRecord({
                    recipient: recipients[i],
                    amount: denomination,
                    timestamp: block.timestamp,
                    batchId: currentBatchId
                })
            );

            emit PaidRecipient(currentBatchId, payoutCount, recipients[i], denomination);
            payoutCount += 1;
        }

        emit BatchPaidOut(currentBatchId, recipients.length, denomination, block.timestamp);
        batchCount += 1;
    }

    function mixerBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getDepositsLength() external view returns (uint256) {
        return deposits.length;
    }

    function getPayoutsLength() external view returns (uint256) {
        return payouts.length;
    }

    function getDeposit(uint256 index)
        external
        view
        returns (
            address depositor,
            uint256 amount,
            uint256 timestamp,
            uint256 batchHint
        )
    {
        DepositRecord memory d = deposits[index];
        return (d.depositor, d.amount, d.timestamp, d.batchHint);
    }

    function getPayout(uint256 index)
        external
        view
        returns (
            address recipient,
            uint256 amount,
            uint256 timestamp,
            uint256 batchId
        )
    {
        PayoutRecord memory p = payouts[index];
        return (p.recipient, p.amount, p.timestamp, p.batchId);
    }
}
