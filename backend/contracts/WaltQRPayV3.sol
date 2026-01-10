// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WaltQRPayV3
 * @notice Multi-token QRIS payment escrow - supports LSK, ETH, POL
 * @dev Based on QrisEscrowV2, adds multi-token support
 */
contract WaltQRPayV3 is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Roles ============
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ============ Enums ============
    enum PaymentStatus { NONE, LOCKED, RELEASED, REFUNDED, DISPUTED, EXPIRED }

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
    mapping(bytes32 => Payment) public payments;
    mapping(address => bool) public whitelistedTokens;
    
    address public feeCollector;
    uint256 public platformFeeBps; // basis points (100 = 1%)
    uint256 public paymentTimeout; // seconds

    Statistics public stats;

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
        string reason
    );

    event TokenWhitelisted(address indexed token, bool status);

    // ============ Constructor ============
    constructor(
        address _admin,
        address _feeCollector,
        uint256 _platformFeeBps,
        uint256 _paymentTimeout
    ) {
        require(_admin != address(0), "Invalid admin");
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_platformFeeBps <= 1000, "Fee too high"); // Max 10%

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);

        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;
        paymentTimeout = _paymentTimeout;
    }

    // ============ Token Whitelist ============
    function setTokenWhitelist(address token, bool status) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        whitelistedTokens[token] = status;
        emit TokenWhitelisted(token, status);
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return whitelistedTokens[token];
    }

    // ============ Payment Functions ============
    
    /**
     * @notice Pay with any whitelisted token (LSK, ETH, POL)
     * @param orderId Unique order identifier (bytes32)
     * @param merchantId QRIS merchant identifier
     * @param token Token address to pay with
     * @param totalAmount Amount to pay in token wei
     */
    function pay(
        bytes32 orderId,
        string calldata merchantId,
        address token,
        uint256 totalAmount
    ) external nonReentrant whenNotPaused {
        require(whitelistedTokens[token], "Token not whitelisted");
        require(payments[orderId].status == PaymentStatus.NONE, "Payment exists");
        require(totalAmount > 0, "Amount must be > 0");

        uint256 fee = (totalAmount * platformFeeBps) / 10000;
        uint256 merchantAmount = totalAmount - fee;
        uint256 expiresAt = block.timestamp + paymentTimeout;

        payments[orderId] = Payment({
            orderId: orderId,
            merchantId: merchantId,
            buyer: msg.sender,
            token: token,
            merchantAmount: merchantAmount,
            platformFee: fee,
            totalPaid: totalAmount,
            lockedAt: block.timestamp,
            expiresAt: expiresAt,
            status: PaymentStatus.LOCKED
        });

        stats.totalPayments++;
        stats.totalVolume += totalAmount;

        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        emit PaymentCreated(
            orderId,
            merchantId,
            msg.sender,
            token,
            merchantAmount,
            fee,
            totalAmount,
            expiresAt
        );
    }

    /**
     * @notice Release payment to merchant (operator only)
     */
    function release(bytes32 orderId) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");

        payment.status = PaymentStatus.RELEASED;
        stats.totalReleased++;
        stats.totalFeesCollected += payment.platformFee;

        // Transfer fee to fee collector
        if (payment.platformFee > 0) {
            IERC20(payment.token).safeTransfer(feeCollector, payment.platformFee);
        }

        // Transfer merchant amount to fee collector (for fiat settlement)
        IERC20(payment.token).safeTransfer(feeCollector, payment.merchantAmount);

        emit PaymentReleased(orderId, payment.merchantAmount, feeCollector);
    }

    /**
     * @notice Refund payment to buyer (operator only)
     */
    function refund(bytes32 orderId, string calldata reason) external onlyRole(OPERATOR_ROLE) nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");

        payment.status = PaymentStatus.REFUNDED;
        stats.totalRefunded++;

        IERC20(payment.token).safeTransfer(payment.buyer, payment.totalPaid);

        emit PaymentRefunded(orderId, payment.totalPaid, payment.buyer, reason);
    }

    /**
     * @notice Dispute payment (buyer only)
     */
    function dispute(bytes32 orderId, string calldata reason) external {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");
        require(msg.sender == payment.buyer, "Not buyer");

        payment.status = PaymentStatus.DISPUTED;
        stats.totalDisputed++;

        emit PaymentDisputed(orderId, reason);
    }

    /**
     * @notice Claim refund for expired payment (buyer only)
     */
    function claimExpiredRefund(bytes32 orderId) external nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Not locked");
        require(block.timestamp > payment.expiresAt, "Not expired");
        require(msg.sender == payment.buyer, "Not buyer");

        payment.status = PaymentStatus.EXPIRED;

        IERC20(payment.token).safeTransfer(payment.buyer, payment.totalPaid);

        emit PaymentRefunded(orderId, payment.totalPaid, payment.buyer, "Expired");
    }

    // ============ View Functions ============
    function getPayment(bytes32 orderId) external view returns (Payment memory) {
        return payments[orderId];
    }

    function getStatistics() external view returns (Statistics memory) {
        return stats;
    }

    function getVersion() external pure returns (string memory) {
        return "WaltQRPay v3.0.0";
    }

    // ============ Admin Functions ============
    function setFeeCollector(address _feeCollector) external onlyRole(ADMIN_ROLE) {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }

    function setPlatformFeeBps(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        require(_feeBps <= 1000, "Fee too high");
        platformFeeBps = _feeBps;
    }

    function setPaymentTimeout(uint256 _timeout) external onlyRole(ADMIN_ROLE) {
        paymentTimeout = _timeout;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
