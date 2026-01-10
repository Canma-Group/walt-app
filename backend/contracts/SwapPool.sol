// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WaltSwap
 * @author Canma Wallet Team
 * @notice Trustless token swap pool with admin fee - Industry Standard Implementation
 * @dev Implements atomic swaps with the following security features:
 *      - Ownable2Step for secure ownership transfer
 *      - ReentrancyGuard for protection against reentrancy attacks
 *      - Pausable for emergency stops
 *      - SafeERC20 for safe token transfers
 *      - Slippage protection
 *      - Deadline protection
 * 
 * Features:
 * - Atomic swaps between supported tokens
 * - 0.2% admin fee sent to fee receiver (hot wallet)
 * - Oracle-based price feeds (simplified for testnet)
 * - Owner can add/remove liquidity
 * - Owner can update exchange rates
 * - Emergency pause functionality
 */
contract WaltSwap is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    /// @notice Protocol version
    string public constant VERSION = "1.0.0";
    
    /// @notice Admin fee in basis points (0.2% = 20 bps)
    uint256 public constant ADMIN_FEE_BPS = 20;
    
    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    /// @notice Maximum admin fee (5% = 500 bps)
    uint256 public constant MAX_ADMIN_FEE_BPS = 500;
    
    /// @notice Price precision (1e18)
    uint256 public constant PRICE_PRECISION = 1e18;

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

    // ============ Structs ============

    struct SwapParams {
        address fromToken;
        address toToken;
        uint256 fromAmount;
        uint256 minToAmount;
        uint256 deadline;
    }

    struct SwapResult {
        uint256 toAmount;
        uint256 adminFee;
        uint256 swapId;
    }

    // ============ Events ============

    event Swap(
        uint256 indexed swapId,
        address indexed user,
        address indexed fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        uint256 adminFee,
        uint256 timestamp
    );
    
    event LiquidityAdded(
        address indexed provider,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    
    event LiquidityRemoved(
        address indexed provider,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    
    event TokenAdded(
        address indexed token,
        uint256 priceUSD,
        uint8 decimals,
        uint256 timestamp
    );
    
    event TokenRemoved(address indexed token, uint256 timestamp);
    
    event PriceUpdated(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );
    
    event FeeReceiverUpdated(
        address indexed oldReceiver,
        address indexed newReceiver,
        uint256 timestamp
    );
    
    event AdminFeeUpdated(
        uint256 oldFee,
        uint256 newFee,
        uint256 timestamp
    );
    
    event EmergencyWithdraw(
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    // ============ Errors ============

    error InvalidAddress();
    error InvalidAmount();
    error InvalidPrice();
    error InvalidFee();
    error TokenNotSupported();
    error TokenAlreadySupported();
    error SameToken();
    error InsufficientLiquidity();
    error SlippageExceeded();
    error DeadlineExpired();
    error TransferFailed();

    // ============ Modifiers ============

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
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
     * @notice Initialize WaltSwap with fee receiver
     * @param _feeReceiver Address to receive admin fees
     */
    constructor(address _feeReceiver) Ownable(msg.sender) {
        if (_feeReceiver == address(0)) revert InvalidAddress();
        feeReceiver = _feeReceiver;
        adminFeeBps = ADMIN_FEE_BPS;
    }

    // ============ External Functions ============

    /**
     * @notice Execute a token swap
     * @param params Swap parameters
     * @return result Swap result containing output amount, fee, and swap ID
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
        
        if (toAmount < params.minToAmount) revert SlippageExceeded();
        if (getPoolBalance(params.toToken) < toAmount) revert InsufficientLiquidity();

        // Increment swap counter
        unchecked {
            swapCounter++;
        }
        uint256 swapId = swapCounter;

        // Transfer fromToken from user to contract
        IERC20(params.fromToken).safeTransferFrom(msg.sender, address(this), params.fromAmount);

        // Transfer admin fee to fee receiver
        if (adminFee > 0) {
            IERC20(params.fromToken).safeTransfer(feeReceiver, adminFee);
            totalFeesCollected[params.fromToken] += adminFee;
        }

        // Transfer toToken to user
        IERC20(params.toToken).safeTransfer(msg.sender, toAmount);

        // Update volume
        totalVolumeSwapped[params.fromToken] += params.fromAmount;

        // Emit event
        emit Swap(
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

    /**
     * @notice Simple swap function for easier integration
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param fromAmount Amount of source token
     * @param minToAmount Minimum output amount (slippage protection)
     */
    function swapSimple(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount
    ) external returns (uint256 toAmount) {
        SwapResult memory result = this.swap(SwapParams({
            fromToken: fromToken,
            toToken: toToken,
            fromAmount: fromAmount,
            minToAmount: minToAmount,
            deadline: 0
        }));
        return result.toAmount;
    }

    // ============ View Functions ============

    /**
     * @notice Calculate swap output amount
     * @param fromToken Source token
     * @param toToken Destination token
     * @param fromAmount Amount of source token
     * @return toAmount Amount of destination token user receives
     * @return adminFee Admin fee in source token
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

        // Calculate admin fee
        adminFee = (fromAmount * adminFeeBps) / BPS_DENOMINATOR;
        uint256 amountAfterFee = fromAmount - adminFee;

        // Calculate output based on USD prices
        uint256 fromPrice = tokenPriceUSD[fromToken];
        uint256 toPrice = tokenPriceUSD[toToken];
        
        // Handle different decimals
        uint8 fromDec = tokenDecimals[fromToken];
        uint8 toDec = tokenDecimals[toToken];
        
        if (fromDec == toDec) {
            toAmount = (amountAfterFee * fromPrice) / toPrice;
        } else if (fromDec > toDec) {
            toAmount = (amountAfterFee * fromPrice) / toPrice / (10 ** (fromDec - toDec));
        } else {
            toAmount = (amountAfterFee * fromPrice * (10 ** (toDec - fromDec))) / toPrice;
        }
    }

    /**
     * @notice Get pool balance for a token
     */
    function getPoolBalance(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get all supported tokens
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    /**
     * @notice Get number of supported tokens
     */
    function getSupportedTokenCount() external view returns (uint256) {
        return tokenList.length;
    }

    /**
     * @notice Get pool info for all tokens
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
     */
    function getExchangeRate(address fromToken, address toToken) 
        external 
        view 
        returns (uint256 rate) 
    {
        if (!supportedTokens[fromToken] || !supportedTokens[toToken]) {
            return 0;
        }
        // Rate = fromPrice / toPrice (scaled by PRICE_PRECISION)
        return (tokenPriceUSD[fromToken] * PRICE_PRECISION) / tokenPriceUSD[toToken];
    }

    // ============ Admin Functions ============

    /**
     * @notice Add a supported token with its USD price
     * @param token Token address
     * @param priceUSD Price in USD scaled by PRICE_PRECISION
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
        
        // Cache decimals
        try IERC20Metadata(token).decimals() returns (uint8 dec) {
            tokenDecimals[token] = dec;
        } catch {
            tokenDecimals[token] = 18; // Default to 18
        }
        
        tokenList.push(token);

        emit TokenAdded(token, priceUSD, tokenDecimals[token], block.timestamp);
    }

    /**
     * @notice Remove a supported token
     */
    function removeToken(address token) 
        external 
        onlyOwner 
        tokenSupported(token) 
    {
        supportedTokens[token] = false;
        tokenPriceUSD[token] = 0;
        tokenDecimals[token] = 0;

        // Remove from list
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
     * @notice Batch update token prices
     */
    function updatePrices(address[] calldata tokens, uint256[] calldata prices) 
        external 
        onlyOwner 
    {
        require(tokens.length == prices.length, "Length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (supportedTokens[tokens[i]] && prices[i] > 0) {
                uint256 oldPrice = tokenPriceUSD[tokens[i]];
                tokenPriceUSD[tokens[i]] = prices[i];
                emit PriceUpdated(tokens[i], oldPrice, prices[i], block.timestamp);
            }
        }
    }

    /**
     * @notice Update fee receiver (hot wallet)
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
     * @notice Update admin fee
     */
    function updateAdminFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_ADMIN_FEE_BPS) revert InvalidFee();
        
        uint256 oldFee = adminFeeBps;
        adminFeeBps = newFeeBps;
        emit AdminFeeUpdated(oldFee, newFeeBps, block.timestamp);
    }

    /**
     * @notice Add liquidity to the pool
     */
    function addLiquidity(address token, uint256 amount) 
        external 
        onlyOwner 
        tokenSupported(token)
        validAmount(amount)
    {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit LiquidityAdded(msg.sender, token, amount, block.timestamp);
    }

    /**
     * @notice Remove liquidity from the pool
     */
    function removeLiquidity(address token, uint256 amount) 
        external 
        onlyOwner 
        tokenSupported(token)
        validAmount(amount)
    {
        if (getPoolBalance(token) < amount) revert InsufficientLiquidity();
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit LiquidityRemoved(msg.sender, token, amount, block.timestamp);
    }

    /**
     * @notice Pause the contract
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
     * @notice Emergency withdraw all tokens (owner only)
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
            emit EmergencyWithdraw(token, balance, block.timestamp);
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
                emit EmergencyWithdraw(token, balance, block.timestamp);
            }
        }
    }
}

// Interface for token decimals
interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
