// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title QrisEscrowV2
 * @notice Enhanced Escrow contract for crypto-to-fiat QRIS payments
 * @dev Implements best practices from ProxyIts competitor contract
 * 
 * Features:
 * - Multi-role access control (ADMIN, OPERATOR, VERIFIER)
 * - Pausable for emergency situations
 * - Whitelisted tokens support
 * - Comprehensive statistics tracking
 * - Emergency withdrawal functions
 * - Configurable fees in basis points
 */
contract QrisEscrowV2 is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Roles ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    // ============ Enums ============
    enum PaymentStatus { NONE, LOCKED, RELEASED, REFUNDED, DISPUTED }

    // ============ Structs ============
    struct Payment {
        bytes32 orderId;
        string merchantId;
        address buyer;
        address token;
        uint256 merchantAmount;
        uint256 platformFee;
        uint256 totalPaid;
        uint256 lockedAt;
        uint256 expiresAt;
        PaymentStatus status;
    }

    struct Statistics {
        uint256 totalPayments;
        uint256 totalReleased;
        uint256 totalRefunded;
        uint256 totalDisputed;
        uint256 totalFeesCollected;
        uint256 totalVolume;
    }

    // ============ State Variables ============
    
    // Whitelisted tokens for payments
    EnumerableSet.AddressSet private whitelistedTokens;
    
    // Default LSK token
    IERC20 public immutable defaultToken;
    
    // orderId => Payment
    mapping(bytes32 => Payment) public payments;
    
    // Statistics
    Statistics public stats;
    
    // Token-specific volume tracking
    mapping(address => uint256) public tokenVolume;
    
    // Configurable parameters
    uint256 public paymentTimeout = 30 minutes;
    uint256 public platformFeeBps = 100; // 1% = 100 basis points, max 10000
    
    // Fee collector address
    address public feeCollector;
    
    // Contract version
    string public constant VERSION = "2.0.0";

    // ============ Events ============
    
    event PaymentCreated(
        bytes32 indexed orderId,
        string merchantId,
        address indexed buyer,
        address indexed token,
        uint256 merchantAmount,
        uint256 platformFee,
        uint256 totalPaid,
        uint256 expiresAt
    );
    
    event PaymentReleased(
        bytes32 indexed orderId,
        uint256 amount,
        address indexed recipient
    );
    
    event PaymentRefunded(
        bytes32 indexed orderId,
        uint256 amount,
        address indexed buyer,
        string reason
    );
    
    event PaymentDisputed(
        bytes32 indexed orderId,
        address indexed disputedBy,
        string reason
    );
    
    event FeeCollected(
        bytes32 indexed orderId,
        uint256 amount,
        address indexed collector
    );
    
    event TokenWhitelisted(address indexed token);
    event TokenRemoved(address indexed token);
    event FeeCollectorUpdated(address indexed newCollector);
    event PlatformFeeUpdated(uint256 newFeeBps);
    event PaymentTimeoutUpdated(uint256 newTimeout);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    // ============ Constructor ============
    
    constructor(address _defaultToken, address _feeCollector) {
        require(_defaultToken != address(0), "Invalid token");
        require(_feeCollector != address(0), "Invalid fee collector");
        
        defaultToken = IERC20(_defaultToken);
        feeCollector = _feeCollector;
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
        
        // Set ADMIN as admin of OPERATOR and VERIFIER roles
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(VERIFIER_ROLE, ADMIN_ROLE);
        
        // Whitelist default token
        whitelistedTokens.add(_defaultToken);
        
        emit TokenWhitelisted(_defaultToken);
    }

    // ============ Modifiers ============
    
    modifier onlyOperatorOrAdmin() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender) || hasRole(ADMIN_ROLE, msg.sender),
            "Not operator or admin"
        );
        _;
    }

    // ============ Core Payment Functions ============
    
    /**
     * @notice Create a payment with automatic fee deduction
     * @param orderId Unique order identifier
     * @param merchantId Merchant identifier from QRIS
     * @param totalAmount Total amount to pay (includes fee)
     */
    function pay(
        bytes32 orderId,
        string calldata merchantId,
        uint256 totalAmount
    ) external whenNotPaused nonReentrant {
        _pay(orderId, merchantId, address(defaultToken), totalAmount);
    }
    
    /**
     * @notice Create a payment with specific token
     * @param orderId Unique order identifier
     * @param merchantId Merchant identifier from QRIS
     * @param token Token address to use
     * @param totalAmount Total amount to pay
     */
    function payWithToken(
        bytes32 orderId,
        string calldata merchantId,
        address token,
        uint256 totalAmount
    ) external whenNotPaused nonReentrant {
        require(whitelistedTokens.contains(token), "Token not whitelisted");
        _pay(orderId, merchantId, token, totalAmount);
    }
    
    /**
     * @dev Internal payment logic
     */
    function _pay(
        bytes32 orderId,
        string calldata merchantId,
        address token,
        uint256 totalAmount
    ) internal {
        require(payments[orderId].status == PaymentStatus.NONE, "Order exists");
        require(totalAmount > 0, "Amount must be > 0");
        require(bytes(merchantId).length > 0, "Merchant ID required");
        
        // Calculate fee
        uint256 platformFee = (totalAmount * platformFeeBps) / 10000;
        uint256 merchantAmount = totalAmount - platformFee;
        require(merchantAmount > 0, "Merchant amount must be > 0");
        
        // Transfer tokens from buyer
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        
        // Send fee to collector immediately
        if (platformFee > 0) {
            IERC20(token).safeTransfer(feeCollector, platformFee);
            stats.totalFeesCollected += platformFee;
            emit FeeCollected(orderId, platformFee, feeCollector);
        }
        
        uint256 expiresAt = block.timestamp + paymentTimeout;
        
        // Store payment
        payments[orderId] = Payment({
            orderId: orderId,
            merchantId: merchantId,
            buyer: msg.sender,
            token: token,
            merchantAmount: merchantAmount,
            platformFee: platformFee,
            totalPaid: totalAmount,
            lockedAt: block.timestamp,
            expiresAt: expiresAt,
            status: PaymentStatus.LOCKED
        });
        
        // Update statistics
        stats.totalPayments++;
        stats.totalVolume += totalAmount;
        tokenVolume[token] += totalAmount;
        
        emit PaymentCreated(
            orderId,
            merchantId,
            msg.sender,
            token,
            merchantAmount,
            platformFee,
            totalAmount,
            expiresAt
        );
    }
    
    /**
     * @notice Release payment to platform for fiat settlement
     */
    function release(bytes32 orderId) external onlyOperatorOrAdmin nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");
        
        payment.status = PaymentStatus.RELEASED;
        stats.totalReleased++;
        
        // Transfer to admin for CEX conversion
        IERC20(payment.token).safeTransfer(msg.sender, payment.merchantAmount);
        
        emit PaymentReleased(orderId, payment.merchantAmount, msg.sender);
    }
    
    /**
     * @notice Refund payment to buyer
     */
    function refund(bytes32 orderId, string calldata reason) 
        external 
        onlyOperatorOrAdmin 
        nonReentrant 
    {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");
        
        payment.status = PaymentStatus.REFUNDED;
        stats.totalRefunded++;
        
        // Return merchant amount to buyer (fee non-refundable)
        IERC20(payment.token).safeTransfer(payment.buyer, payment.merchantAmount);
        
        emit PaymentRefunded(orderId, payment.merchantAmount, payment.buyer, reason);
    }
    
    /**
     * @notice Buyer can claim refund after expiration
     */
    function claimExpiredRefund(bytes32 orderId) external nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");
        require(payment.buyer == msg.sender, "Not buyer");
        require(block.timestamp > payment.expiresAt, "Not expired");
        
        payment.status = PaymentStatus.REFUNDED;
        stats.totalRefunded++;
        
        IERC20(payment.token).safeTransfer(payment.buyer, payment.merchantAmount);
        
        emit PaymentRefunded(orderId, payment.merchantAmount, payment.buyer, "Expired");
    }
    
    /**
     * @notice Mark payment as disputed
     */
    function dispute(bytes32 orderId, string calldata reason) 
        external 
        onlyRole(VERIFIER_ROLE) 
    {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");
        
        payment.status = PaymentStatus.DISPUTED;
        stats.totalDisputed++;
        
        emit PaymentDisputed(orderId, msg.sender, reason);
    }

    // ============ Token Whitelist Management ============
    
    function addWhitelistedToken(address token) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(whitelistedTokens.add(token), "Already whitelisted");
        emit TokenWhitelisted(token);
    }
    
    function removeWhitelistedToken(address token) external onlyRole(ADMIN_ROLE) {
        require(token != address(defaultToken), "Cannot remove default");
        require(whitelistedTokens.remove(token), "Not whitelisted");
        emit TokenRemoved(token);
    }
    
    function isTokenWhitelisted(address token) external view returns (bool) {
        return whitelistedTokens.contains(token);
    }
    
    function getWhitelistedTokensCount() external view returns (uint256) {
        return whitelistedTokens.length();
    }
    
    function getWhitelistedTokenAt(uint256 index) external view returns (address) {
        require(index < whitelistedTokens.length(), "Index out of bounds");
        return whitelistedTokens.at(index);
    }

    // ============ Admin Functions ============
    
    function setFeeCollector(address _feeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(_feeCollector);
    }
    
    function setPlatformFeeBps(uint256 _feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeBps <= 500, "Max 5%"); // Max 500 bps = 5%
        platformFeeBps = _feeBps;
        emit PlatformFeeUpdated(_feeBps);
    }
    
    function setPaymentTimeout(uint256 _timeout) external onlyRole(ADMIN_ROLE) {
        require(_timeout >= 5 minutes && _timeout <= 24 hours, "Invalid timeout");
        paymentTimeout = _timeout;
        emit PaymentTimeoutUpdated(_timeout);
    }
    
    // ============ Pausable ============
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============ Emergency Functions ============
    
    function emergencyWithdrawETH(address payable to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH");
        to.transfer(balance);
        emit EmergencyWithdraw(address(0), to, balance);
    }
    
    function emergencyWithdrawToken(address token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens");
        IERC20(token).safeTransfer(to, balance);
        emit EmergencyWithdraw(token, to, balance);
    }

    // ============ View Functions ============
    
    function getPayment(bytes32 orderId) external view returns (Payment memory) {
        return payments[orderId];
    }
    
    function getStatistics() external view returns (Statistics memory) {
        return stats;
    }
    
    function getTokenVolume(address token) external view returns (uint256) {
        return tokenVolume[token];
    }
    
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }

    // ============ Role Management ============
    
    function addOperator(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(OPERATOR_ROLE, account);
    }
    
    function removeOperator(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(OPERATOR_ROLE, account);
    }
    
    function addVerifier(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(VERIFIER_ROLE, account);
    }
    
    function removeVerifier(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(VERIFIER_ROLE, account);
    }

    // ============ Receive ETH ============
    
    receive() external payable {}
}
