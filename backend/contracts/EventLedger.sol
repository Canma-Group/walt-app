// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EventLedger
 * @dev Simple event-only ledger for cross-chain transaction recording
 * Does NOT store balances - only emits events for explorer visibility
 */
contract EventLedger {
    address public owner;
    address public operator;

    event DepositRecorded(
        address indexed user,
        string token,
        string sourceChain,
        uint256 amount,
        string sourceTxHash,
        uint256 timestamp
    );

    event WithdrawalRecorded(
        address indexed user,
        string token,
        string destChain,
        uint256 amount,
        string destTxHash,
        uint256 timestamp
    );

    modifier onlyOperator() {
        require(msg.sender == operator || msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
        operator = msg.sender;
    }

    function setOperator(address _operator) external {
        require(msg.sender == owner, "Only owner");
        operator = _operator;
    }

    function recordDeposit(
        address user,
        string calldata token,
        string calldata sourceChain,
        uint256 amount,
        string calldata sourceTxHash
    ) external onlyOperator {
        emit DepositRecorded(
            user,
            token,
            sourceChain,
            amount,
            sourceTxHash,
            block.timestamp
        );
    }

    function recordWithdrawal(
        address user,
        string calldata token,
        string calldata destChain,
        uint256 amount,
        string calldata destTxHash
    ) external onlyOperator {
        emit WithdrawalRecorded(
            user,
            token,
            destChain,
            amount,
            destTxHash,
            block.timestamp
        );
    }

    function recordBatch(
        address[] calldata users,
        string[] calldata tokens,
        string[] calldata sourceChains,
        uint256[] calldata amounts,
        string[] calldata sourceTxHashes
    ) external onlyOperator {
        require(
            users.length == tokens.length &&
            users.length == sourceChains.length &&
            users.length == amounts.length &&
            users.length == sourceTxHashes.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < users.length; i++) {
            emit DepositRecorded(
                users[i],
                tokens[i],
                sourceChains[i],
                amounts[i],
                sourceTxHashes[i],
                block.timestamp
            );
        }
    }
}
