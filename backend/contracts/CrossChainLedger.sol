// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CrossChainLedger
 * @dev Records cross-chain deposits as a ledger on Lisk Sepolia
 * This contract does NOT hold actual assets - it only records claims/balances
 * from deposits that occurred on other chains (e.g., Polygon)
 */
contract CrossChainLedger {
    // ============ State Variables ============
    address public owner;
    address public operator;
    
    // Mapping: user => chainId => token => balance
    mapping(address => mapping(uint256 => mapping(address => uint256))) public balances;
    
    // Mapping: chainId => txHash => processed (anti double-credit)
    mapping(uint256 => mapping(bytes32 => bool)) public processedTx;
    
    // Supported chains
    mapping(uint256 => bool) public supportedChains;
    
    // Token info for display
    struct TokenInfo {
        string symbol;
        string name;
        uint8 decimals;
        bool active;
    }
    
    // Mapping: chainId => tokenAddress => TokenInfo
    mapping(uint256 => mapping(address => TokenInfo)) public tokenInfo;
    
    // ============ Events ============
    event DepositRecorded(
        address indexed user,
        uint256 indexed sourceChainId,
        address indexed token,
        uint256 amount,
        bytes32 sourceTxHash,
        uint256 timestamp
    );
    
    event WithdrawalRecorded(
        address indexed user,
        uint256 indexed chainId,
        address indexed token,
        uint256 amount,
        string reason
    );
    
    event ChainAdded(uint256 chainId, string name);
    event TokenRegistered(uint256 chainId, address token, string symbol, string name, uint8 decimals);
    event OperatorUpdated(address oldOperator, address newOperator);
    
    // ============ Modifiers ============
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyOperator() {
        require(msg.sender == operator || msg.sender == owner, "Only operator");
        _;
    }
    
    // ============ Constructor ============
    constructor() {
        owner = msg.sender;
        operator = msg.sender;
        
        // Add Polygon (chainId 137 for mainnet, 80002 for Amoy testnet, 80001 for Mumbai)
        supportedChains[137] = true;    // Polygon Mainnet
        supportedChains[80001] = true;  // Polygon Mumbai (deprecated)
        supportedChains[80002] = true;  // Polygon Amoy
        
        // Add Ethereum
        supportedChains[1] = true;      // Ethereum Mainnet
        supportedChains[11155111] = true; // Sepolia
        
        // Native token address (address(0) represents native coin like POL/ETH)
        // Register POL on Polygon
        tokenInfo[137][address(0)] = TokenInfo("POL", "Polygon", 18, true);
        tokenInfo[80001][address(0)] = TokenInfo("MATIC", "Polygon Mumbai", 18, true);
        tokenInfo[80002][address(0)] = TokenInfo("POL", "Polygon Amoy", 18, true);
        
        // Register ETH on Ethereum
        tokenInfo[1][address(0)] = TokenInfo("ETH", "Ethereum", 18, true);
        tokenInfo[11155111][address(0)] = TokenInfo("ETH", "Sepolia ETH", 18, true);
    }
    
    // ============ Admin Functions ============
    function setOperator(address _operator) external onlyOwner {
        emit OperatorUpdated(operator, _operator);
        operator = _operator;
    }
    
    function addSupportedChain(uint256 chainId, string calldata name) external onlyOwner {
        supportedChains[chainId] = true;
        emit ChainAdded(chainId, name);
    }
    
    function registerToken(
        uint256 chainId,
        address token,
        string calldata symbol,
        string calldata name,
        uint8 decimals
    ) external onlyOperator {
        tokenInfo[chainId][token] = TokenInfo(symbol, name, decimals, true);
        emit TokenRegistered(chainId, token, symbol, name, decimals);
    }
    
    // ============ Core Functions ============
    
    /**
     * @dev Record a deposit from another chain (called by backend operator)
     * @param user The user's wallet address
     * @param sourceChainId The chain where deposit occurred (e.g., 137 for Polygon)
     * @param token The token address on source chain (address(0) for native)
     * @param amount The amount deposited (in wei)
     * @param sourceTxHash The transaction hash on source chain
     */
    function recordDeposit(
        address user,
        uint256 sourceChainId,
        address token,
        uint256 amount,
        bytes32 sourceTxHash
    ) external onlyOperator {
        require(user != address(0), "Invalid user");
        require(supportedChains[sourceChainId], "Unsupported chain");
        require(amount > 0, "Amount must be > 0");
        require(!processedTx[sourceChainId][sourceTxHash], "Tx already processed");
        
        // Mark as processed
        processedTx[sourceChainId][sourceTxHash] = true;
        
        // Credit balance
        balances[user][sourceChainId][token] += amount;
        
        emit DepositRecorded(
            user,
            sourceChainId,
            token,
            amount,
            sourceTxHash,
            block.timestamp
        );
    }
    
    /**
     * @dev Record multiple deposits in one transaction (batch)
     */
    function recordDepositsBatch(
        address[] calldata users,
        uint256[] calldata sourceChainIds,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata sourceTxHashes
    ) external onlyOperator {
        require(
            users.length == sourceChainIds.length &&
            users.length == tokens.length &&
            users.length == amounts.length &&
            users.length == sourceTxHashes.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < users.length; i++) {
            if (!processedTx[sourceChainIds[i]][sourceTxHashes[i]]) {
                processedTx[sourceChainIds[i]][sourceTxHashes[i]] = true;
                balances[users[i]][sourceChainIds[i]][tokens[i]] += amounts[i];
                
                emit DepositRecorded(
                    users[i],
                    sourceChainIds[i],
                    tokens[i],
                    amounts[i],
                    sourceTxHashes[i],
                    block.timestamp
                );
            }
        }
    }
    
    /**
     * @dev Debit/reduce balance (for withdrawals, swaps, etc.)
     */
    function recordWithdrawal(
        address user,
        uint256 chainId,
        address token,
        uint256 amount,
        string calldata reason
    ) external onlyOperator {
        require(balances[user][chainId][token] >= amount, "Insufficient balance");
        
        balances[user][chainId][token] -= amount;
        
        emit WithdrawalRecorded(user, chainId, token, amount, reason);
    }
    
    // ============ View Functions ============
    
    /**
     * @dev Get user's balance for a specific token on a specific chain
     */
    function getBalance(
        address user,
        uint256 chainId,
        address token
    ) external view returns (uint256) {
        return balances[user][chainId][token];
    }
    
    /**
     * @dev Check if a transaction has been processed
     */
    function isTxProcessed(uint256 chainId, bytes32 txHash) external view returns (bool) {
        return processedTx[chainId][txHash];
    }
    
    /**
     * @dev Get token info
     */
    function getTokenInfo(uint256 chainId, address token) external view returns (
        string memory symbol,
        string memory name,
        uint8 decimals,
        bool active
    ) {
        TokenInfo memory info = tokenInfo[chainId][token];
        return (info.symbol, info.name, info.decimals, info.active);
    }
}
