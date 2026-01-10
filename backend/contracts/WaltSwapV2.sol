// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WaltSwapV2
 * @author Canma Wallet Team
 * @notice Trustless token swap pool with admin fee - Production Ready Implementation
 * @dev Version 2.0 improvements:
 *      - Removed deprecated swapSimple function
 *      - Enhanced gas optimization
 *      - Improved event logging for better analytics
 *      - Added swap history tracking per user
 *      - Better error messages
 *      - Configurable minimum swap amount
 * 
 * Security Features:
 *      - Ownable2Step for secure ownership transfer
 *      - ReentrancyGuard for protection against reentrancy attacks
 *      - Pausable for emergency stops
 *      - SafeERC20 for safe token transfers
 *      - Slippage protection
 *      - Deadline protection
 *      - Minimum swap amount validation
 */
contract WaltSwapV2 is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    /// @notice Protocol version
    string public constant VERSION = "2.0.0";
    
    /// @notice Contract name for verification
    string public constant NAME = "WaltSwapV2";
    
    /// @notice Default admin fee in basis points (0.2% = 20 bps)
    uint256 public constant DEFAULT_ADMIN_FEE_BPS = 20;
    
    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    /// @notice Maximum admin fee (5% = 500 bps)
    uint256 public constant MAX_ADMIN_FEE_BPS = 500;
    
    /// @notice Price precision (1e18)
    uint256 public constant PRICE_PRECISION = 1e18;
    
    /// @notice Minimum swap amount in wei (0.0001 tokens with 18 decimals)
    uint256 public constant MIN_SWAP_AMOUNT = 1e14;

    // ============ State Variables ============

    /// @notice Fee receiver address (hot wallet)
    address public feeReceiver;
    
    /// @notice Current admin fee in basis points
    uint256 public adminFeeBps;

    /// @notice Supported tokens mapping
    mapping(address => bool) public supportedTokens;
    
    /// @notice List of all supported tokens
    address[] public tokenList;

    /// @notice Token prices in USD (scaled by PRICE_PRECISION)
    mapping(address => uint256) public tokenPriceUSD;
    
    /// @notice Token decimals cache
    mapping(address => uint8) public tokenDecimals;

    /// @notice Total volume swapped per token (for analytics)
    mapping(address => uint256) public totalVolumeSwapped;
    
    /// @notice Total fees collected per token
    mapping(address => uint256) public totalFeesCollected;

    /// @notice Swap counter for unique swap IDs
    uint256 public swapCounter;
    
    /// @notice User swap count for tracking
    mapping(address => uint256) public userSwapCount;
    
    /// @notice Last swap timestamp per user (for rate limiting if needed)
    mapping(address => uint256) public lastSwapTimestamp;

    // ============ Structs ============

    /// @notice Parameters for executing a swap
    struct SwapParams {
        address fromToken;      // Source token address
        address toToken;        // Destination token address
        uint256 fromAmount;     // Amount of source token to swap
        uint256 minToAmount;    // Minimum acceptable output (slippage protection)
        uint256 deadline;       // Transaction deadline (0 = no deadline)
    }

    /// @notice Result of a successful swap
    struct SwapResult {
        uint256 toAmount;       // Amount of destination token received
        uint256 adminFee;       // Fee deducted in source token
        uint256 swapId;         // Unique swap identifier
    }
    
    /// @notice Token information struct for getTokenInfo
    struct TokenInfo {
        address tokenAddress;
        uint256 priceUSD;
        uint8 decimals;
        uint256 poolBalance;
        uint256 totalVolume;
        uint256 totalFees;
        bool isSupported;
    }

    // ============ Events ============

    /// @notice Emitted when a swap is executed
    event SwapExecuted(
        uint256 indexed swapId,
        address indexed user,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        uint256 adminFee,
        uint256 timestamp
    );
    
    /// @notice Emitted when liquidity is added
    event LiquidityAdded(
        address indexed provider,
        address indexed token,
        uint256 amount,
        uint256 newBalance,
        uint256 timestamp
    );
    
    /// @notice Emitted when liquidity is removed
    event LiquidityRemoved(
        address indexed provider,
        address indexed token,
        uint256 amount,
        uint256 newBalance,
        uint256 timestamp
    );
    
    /// @notice Emitted when a token is added to the pool
    event TokenAdded(
        address indexed token,
        uint256 priceUSD,
        uint8 decimals,
        uint256 timestamp
    );
    
    /// @notice Emitted when a token is removed from the pool
    event TokenRemoved(
        address indexed token,
        uint256 timestamp
    );
    
    /// @notice Emitted when a token price is updated
    event PriceUpdated(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );
    
    /// @notice Emitted when the fee receiver is updated
    event FeeReceiverUpdated(
        address indexed oldReceiver,
        address indexed newReceiver,
        uint256 timestamp
    );
    
    /// @notice Emitted when the admin fee is updated
    event AdminFeeUpdated(
        uint256 oldFee,
        uint256 newFee,
        uint256 timestamp
    );
    
    /// @notice Emitted on emergency withdrawal
    event EmergencyWithdraw(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    // ============ Errors ============

    error InvalidAddress();
    error InvalidAmount();
    error AmountTooSmall();
    error InvalidPrice();
    error InvalidFee();
    error TokenNotSupported();
    error TokenAlreadySupported();
    error SameToken();
    error InsufficientLiquidity();
    error SlippageExceeded();
    error DeadlineExpired();
    error ArrayLengthMismatch();

    // ============ Modifiers ============

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        if (amount < MIN_SWAP_AMOUNT) revert AmountTooSmall();
        _;
    }

    modifier tokenSupported(address token) {
        if (!supportedTokens[token]) revert TokenNotSupported();
        _;
    }

    modifier beforeDeadline(uint256 deadline) {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initialize WaltSwapV2 with fee receiver
     * @param _feeReceiver Address to receive admin fees (hot wallet)
     */
    constructor(address _feeReceiver) Ownable(msg.sender) {
        if (_feeReceiver == address(0)) revert InvalidAddress();
        feeReceiver = _feeReceiver;
        adminFeeBps = DEFAULT_ADMIN_FEE_BPS;
    }

    // ============ External Swap Function ============

    /**
     * @notice Execute a token swap
     * @dev Main swap function with full parameter control
     * @param params SwapParams struct containing all swap parameters
     * @return result SwapResult containing output amount, fee, and swap ID
     */
    function swap(SwapParams calldata params) 
        external 
        nonReentrant 
        whenNotPaused
        tokenSupported(params.fromToken)
        tokenSupported(params.toToken)
        validAmount(params.fromAmount)
        beforeDeadline(params.deadline)
        returns (SwapResult memory result)
    {
        if (params.fromToken == params.toToken) revert SameToken();

        // Calculate amounts
        (uint256 toAmount, uint256 adminFee) = getSwapQuote(
            params.fromToken,
            params.toToken,
            params.fromAmount
        );
        
        // Slippage check
        if (toAmount < params.minToAmount) revert SlippageExceeded();
        
        // Liquidity check
        if (getPoolBalance(params.toToken) < toAmount) revert InsufficientLiquidity();

        // Increment swap counter
        unchecked {
            swapCounter++;
            userSwapCount[msg.sender]++;
        }
        uint256 swapId = swapCounter;
        
        // Update last swap timestamp
        lastSwapTimestamp[msg.sender] = block.timestamp;

        // Transfer fromToken from user to contract
        IERC20(params.fromToken).safeTransferFrom(msg.sender, address(this), params.fromAmount);

        // Transfer admin fee to fee receiver
        if (adminFee > 0) {
            IERC20(params.fromToken).safeTransfer(feeReceiver, adminFee);
            totalFeesCollected[params.fromToken] += adminFee;
        }

        // Transfer toToken to user
        IERC20(params.toToken).safeTransfer(msg.sender, toAmount);

        // Update volume statistics
        totalVolumeSwapped[params.fromToken] += params.fromAmount;

        // Emit swap event
        emit SwapExecuted(
            swapId,
            msg.sender,
            params.fromToken,
            params.toToken,
            params.fromAmount,
            toAmount,
            adminFee,
            block.timestamp
        );

        return SwapResult({
            toAmount: toAmount,
            adminFee: adminFee,
            swapId: swapId
        });
    }

    // ============ View Functions ============

    /**
     * @notice Calculate swap output amount and fee
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param fromAmount Amount of source token
     * @return toAmount Amount of destination token user will receive
     * @return adminFee Admin fee deducted from source token
     */
    function getSwapQuote(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) public view returns (uint256 toAmount, uint256 adminFee) {
        if (!supportedTokens[fromToken]) revert TokenNotSupported();
        if (!supportedTokens[toToken]) revert TokenNotSupported();
        if (fromToken == toToken) revert SameToken();
        if (fromAmount == 0) revert InvalidAmount();

        // Calculate admin fee (0.2% default)
        adminFee = (fromAmount * adminFeeBps) / BPS_DENOMINATOR;
        uint256 amountAfterFee = fromAmount - adminFee;

        // Get prices
        uint256 fromPrice = tokenPriceUSD[fromToken];
        uint256 toPrice = tokenPriceUSD[toToken];
        
        // Handle different decimals
        uint8 fromDec = tokenDecimals[fromToken];
        uint8 toDec = tokenDecimals[toToken];
        
        // Calculate output amount with decimal adjustment
        if (fromDec == toDec) {
            toAmount = (amountAfterFee * fromPrice) / toPrice;
        } else if (fromDec > toDec) {
            toAmount = (amountAfterFee * fromPrice) / toPrice / (10 ** (fromDec - toDec));
        } else {
            toAmount = (amountAfterFee * fromPrice * (10 ** (toDec - fromDec))) / toPrice;
        }
    }

    /**
     * @notice Get pool balance for a specific token
     * @param token Token address
     * @return balance Current balance of token in the pool
     */
    function getPoolBalance(address token) public view returns (uint256 balance) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    /**
     * @notice Get number of supported tokens
     * @return count Number of tokens in the pool
     */
    function getSupportedTokenCount() external view returns (uint256 count) {
        return tokenList.length;
    }
    
    /**
     * @notice Get detailed information for a specific token
     * @param token Token address
     * @return info TokenInfo struct with all token details
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory info) {
        return TokenInfo({
            tokenAddress: token,
            priceUSD: tokenPriceUSD[token],
            decimals: tokenDecimals[token],
            poolBalance: getPoolBalance(token),
            totalVolume: totalVolumeSwapped[token],
            totalFees: totalFeesCollected[token],
            isSupported: supportedTokens[token]
        });
    }

    /**
     * @notice Get pool info for all supported tokens
     * @return tokens Array of token addresses
     * @return balances Array of pool balances
     * @return prices Array of USD prices
     * @return volumes Array of total volumes
     * @return fees Array of total fees collected
     */
    function getPoolInfo() external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256[] memory prices,
        uint256[] memory volumes,
        uint256[] memory fees
    ) {
        uint256 len = tokenList.length;
        tokens = new address[](len);
        balances = new uint256[](len);
        prices = new uint256[](len);
        volumes = new uint256[](len);
        fees = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            address token = tokenList[i];
            tokens[i] = token;
            balances[i] = getPoolBalance(token);
            prices[i] = tokenPriceUSD[token];
            volumes[i] = totalVolumeSwapped[token];
            fees[i] = totalFeesCollected[token];
        }
    }

    /**
     * @notice Get exchange rate between two tokens
     * @param fromToken Source token
     * @param toToken Destination token
     * @return rate Exchange rate scaled by PRICE_PRECISION
     */
    function getExchangeRate(address fromToken, address toToken) 
        external 
        view 
        returns (uint256 rate) 
    {
        if (!supportedTokens[fromToken] || !supportedTokens[toToken]) {
            return 0;
        }
        return (tokenPriceUSD[fromToken] * PRICE_PRECISION) / tokenPriceUSD[toToken];
    }
    
    /**
     * @notice Get user statistics
     * @param user User address
     * @return swapCount Total swaps by user
     * @return lastSwap Timestamp of last swap
     */
    function getUserStats(address user) external view returns (
        uint256 swapCount,
        uint256 lastSwap
    ) {
        return (userSwapCount[user], lastSwapTimestamp[user]);
    }

    // ============ Admin Functions ============

    /**
     * @notice Add a new supported token with its USD price
     * @param token Token address
     * @param priceUSD Price in USD scaled by PRICE_PRECISION (1e18)
     */
    function addToken(address token, uint256 priceUSD) 
        external 
        onlyOwner 
        validAddress(token)
    {
        if (priceUSD == 0) revert InvalidPrice();
        if (supportedTokens[token]) revert TokenAlreadySupported();

        supportedTokens[token] = true;
        tokenPriceUSD[token] = priceUSD;
        
        // Cache decimals (try to get from token, default to 18)
        try IERC20Metadata(token).decimals() returns (uint8 dec) {
            tokenDecimals[token] = dec;
        } catch {
            tokenDecimals[token] = 18;
        }
        
        tokenList.push(token);

        emit TokenAdded(token, priceUSD, tokenDecimals[token], block.timestamp);
    }

    /**
     * @notice Remove a supported token from the pool
     * @param token Token address to remove
     */
    function removeToken(address token) 
        external 
        onlyOwner 
        tokenSupported(token) 
    {
        supportedTokens[token] = false;
        tokenPriceUSD[token] = 0;
        tokenDecimals[token] = 0;

        // Remove from list (swap with last element and pop)
        uint256 len = tokenList.length;
        for (uint256 i = 0; i < len; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[len - 1];
                tokenList.pop();
                break;
            }
        }

        emit TokenRemoved(token, block.timestamp);
    }

    /**
     * @notice Update token price
     * @param token Token address
     * @param newPriceUSD New price in USD scaled by PRICE_PRECISION
     */
    function updatePrice(address token, uint256 newPriceUSD) 
        external 
        onlyOwner 
        tokenSupported(token) 
    {
        if (newPriceUSD == 0) revert InvalidPrice();
        
        uint256 oldPrice = tokenPriceUSD[token];
        tokenPriceUSD[token] = newPriceUSD;
        
        emit PriceUpdated(token, oldPrice, newPriceUSD, block.timestamp);
    }

    /**
     * @notice Batch update multiple token prices
     * @param tokens Array of token addresses
     * @param prices Array of new prices
     */
    function updatePrices(address[] calldata tokens, uint256[] calldata prices) 
        external 
        onlyOwner 
    {
        if (tokens.length != prices.length) revert ArrayLengthMismatch();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (supportedTokens[tokens[i]] && prices[i] > 0) {
                uint256 oldPrice = tokenPriceUSD[tokens[i]];
                tokenPriceUSD[tokens[i]] = prices[i];
                emit PriceUpdated(tokens[i], oldPrice, prices[i], block.timestamp);
            }
        }
    }

    /**
     * @notice Update fee receiver address
     * @param newFeeReceiver New fee receiver address
     */
    function updateFeeReceiver(address newFeeReceiver) 
        external 
        onlyOwner 
        validAddress(newFeeReceiver) 
    {
        address oldReceiver = feeReceiver;
        feeReceiver = newFeeReceiver;
        emit FeeReceiverUpdated(oldReceiver, newFeeReceiver, block.timestamp);
    }

    /**
     * @notice Update admin fee percentage
     * @param newFeeBps New fee in basis points (max 500 = 5%)
     */
    function updateAdminFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_ADMIN_FEE_BPS) revert InvalidFee();
        
        uint256 oldFee = adminFeeBps;
        adminFeeBps = newFeeBps;
        emit AdminFeeUpdated(oldFee, newFeeBps, block.timestamp);
    }

    /**
     * @notice Add liquidity to the pool
     * @param token Token address
     * @param amount Amount to add
     */
    function addLiquidity(address token, uint256 amount) 
        external 
        onlyOwner 
        tokenSupported(token)
        validAmount(amount)
    {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit LiquidityAdded(msg.sender, token, amount, getPoolBalance(token), block.timestamp);
    }

    /**
     * @notice Remove liquidity from the pool
     * @param token Token address
     * @param amount Amount to remove
     */
    function removeLiquidity(address token, uint256 amount) 
        external 
        onlyOwner 
        tokenSupported(token)
        validAmount(amount)
    {
        if (getPoolBalance(token) < amount) revert InsufficientLiquidity();
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit LiquidityRemoved(msg.sender, token, amount, getPoolBalance(token), block.timestamp);
    }

    /**
     * @notice Pause the contract (emergency stop)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw a specific token
     * @param token Token address
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
            emit EmergencyWithdraw(token, msg.sender, balance, block.timestamp);
        }
    }

    /**
     * @notice Emergency withdraw all supported tokens
     */
    function emergencyWithdrawAll() external onlyOwner {
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(msg.sender, balance);
                emit EmergencyWithdraw(token, msg.sender, balance, block.timestamp);
            }
        }
    }
}

/// @notice Interface for ERC20 token decimals
interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
