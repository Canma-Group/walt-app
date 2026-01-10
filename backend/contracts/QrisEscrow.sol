// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title QrisEscrow
 * @notice Escrow contract for crypto-to-fiat QRIS payments on Lisk Mainnet
 * @dev Handles LSK token deposits, locks funds, and emits events for backend processing
 * 
 * HACKATHON MVP - Not for production use
 * 
 * Flow:
 * 1. Buyer calls pay() with LSK tokens
 * 2. Contract locks tokens and emits PaymentLocked event
 * 3. Backend listens to events, processes conversion, and settles
 * 4. Admin can release or refund funds
 */
contract QrisEscrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============
    
    IERC20 public immutable lskToken;
    
    enum PaymentStatus { NONE, LOCKED, RELEASED, REFUNDED }
    
    struct Payment {
        bytes32 orderId;
        string merchantId;
        address buyer;
        uint256 merchantAmount;     // Amount for merchant (locked)
        uint256 adminFee;           // Fee taken by admin
        uint256 totalPaid;          // Total paid by user
        uint256 lockedAt;
        uint256 expiresAt;
        PaymentStatus status;
    }
    
    // orderId => Payment
    mapping(bytes32 => Payment) public payments;
    
    // txHash => processed (for idempotency)
    mapping(bytes32 => bool) public processedTxHashes;
    
    // Configurable parameters
    uint256 public paymentTimeout = 30 minutes;
    uint256 public platformFeePercent = 100; // 1% = 100 basis points
    
    // Platform fee collector
    address public feeCollector;
    
    // Statistics
    uint256 public totalFeesCollected;
    uint256 public totalMerchantVolume;

    // ============ Events ============
    
    /**
     * @notice Emitted when a payment is locked with fee split
     * @param orderId Unique order identifier
     * @param merchantId Merchant identifier (from QRIS)
     * @param merchantAmount Amount locked for merchant
     * @param adminFee Fee sent to admin wallet
     * @param totalPaid Total paid by buyer
     * @param buyerAddress Address of the buyer
     * @param expiresAt Timestamp when payment expires
     */
    event PaymentLockedWithFee(
        bytes32 indexed orderId,
        string merchantId,
        uint256 merchantAmount,
        uint256 adminFee,
        uint256 totalPaid,
        address indexed buyerAddress,
        uint256 expiresAt
    );
    
    /**
     * @notice Emitted when admin fee is collected
     * @param orderId Order that generated the fee
     * @param amount Fee amount in LSK
     * @param recipient Admin wallet address
     */
    event AdminFeeCollected(
        bytes32 indexed orderId,
        uint256 amount,
        address indexed recipient
    );
    
    /**
     * @notice Emitted when payment is released to platform for conversion
     * @param orderId Unique order identifier
     * @param amount Amount released to platform
     */
    event PaymentReleased(
        bytes32 indexed orderId,
        uint256 amount
    );
    
    /**
     * @notice Emitted when payment is refunded to buyer
     * @param orderId Unique order identifier
     * @param amount Amount refunded (merchant amount only, fee non-refundable)
     * @param reason Refund reason
     */
    event PaymentRefunded(
        bytes32 indexed orderId,
        uint256 amount,
        string reason
    );

    // ============ Constructor ============
    
    /**
     * @param _lskToken Address of LSK token on Lisk Mainnet
     * @param _feeCollector Address to receive platform fees
     */
    constructor(address _lskToken, address _feeCollector) Ownable(msg.sender) {
        require(_lskToken != address(0), "Invalid LSK token address");
        require(_feeCollector != address(0), "Invalid fee collector");
        
        lskToken = IERC20(_lskToken);
        feeCollector = _feeCollector;
    }

    // ============ Core Functions ============
    
    /**
     * @notice Pay with fee split - Admin fee sent immediately, merchant amount locked
     * @param orderId Unique order identifier (payment_id from backend)
     * @param merchantId Merchant identifier from QRIS
     * @param totalAmount Total LSK to pay (merchantAmount + adminFee)
     * 
     * The contract will:
     * 1. Calculate admin fee (platformFeePercent of totalAmount)
     * 2. Send admin fee directly to feeCollector (admin wallet)
     * 3. Lock remaining amount in escrow for merchant
     * 
     * Requirements:
     * - orderId must not already exist
     * - totalAmount must be > 0
     * - Buyer must have approved this contract to spend LSK
     */
    function payWithFee(
        bytes32 orderId,
        string calldata merchantId,
        uint256 totalAmount
    ) external nonReentrant {
        require(payments[orderId].status == PaymentStatus.NONE, "Order already exists");
        require(totalAmount > 0, "Amount must be greater than 0");
        require(bytes(merchantId).length > 0, "Merchant ID required");
        
        // Calculate fee split
        uint256 adminFee = (totalAmount * platformFeePercent) / 10000;
        uint256 merchantAmount = totalAmount - adminFee;
        
        require(merchantAmount > 0, "Merchant amount must be > 0");
        
        // Transfer total LSK from buyer to this contract first
        lskToken.safeTransferFrom(msg.sender, address(this), totalAmount);
        
        // Immediately send admin fee to feeCollector (admin wallet)
        if (adminFee > 0) {
            lskToken.safeTransfer(feeCollector, adminFee);
            totalFeesCollected += adminFee;
            
            emit AdminFeeCollected(orderId, adminFee, feeCollector);
        }
        
        uint256 expiresAt = block.timestamp + paymentTimeout;
        
        // Store payment (only merchant amount is locked)
        payments[orderId] = Payment({
            orderId: orderId,
            merchantId: merchantId,
            buyer: msg.sender,
            merchantAmount: merchantAmount,
            adminFee: adminFee,
            totalPaid: totalAmount,
            lockedAt: block.timestamp,
            expiresAt: expiresAt,
            status: PaymentStatus.LOCKED
        });
        
        // Update statistics
        totalMerchantVolume += merchantAmount;
        
        // Emit event for backend listener
        emit PaymentLockedWithFee(
            orderId,
            merchantId,
            merchantAmount,
            adminFee,
            totalAmount,
            msg.sender,
            expiresAt
        );
    }
    
    /**
     * @notice Legacy pay function (no fee split, for backwards compatibility)
     * @dev Fee will be taken at release() instead
     */
    function pay(
        bytes32 orderId,
        string calldata merchantId,
        uint256 amount
    ) external nonReentrant {
        require(payments[orderId].status == PaymentStatus.NONE, "Order already exists");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(merchantId).length > 0, "Merchant ID required");
        
        // Transfer LSK from buyer to this contract
        lskToken.safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 expiresAt = block.timestamp + paymentTimeout;
        
        // Store payment (legacy format - all as merchantAmount)
        payments[orderId] = Payment({
            orderId: orderId,
            merchantId: merchantId,
            buyer: msg.sender,
            merchantAmount: amount,
            adminFee: 0,
            totalPaid: amount,
            lockedAt: block.timestamp,
            expiresAt: expiresAt,
            status: PaymentStatus.LOCKED
        });
        
        // Emit legacy event format
        emit PaymentLockedWithFee(
            orderId,
            merchantId,
            amount,
            0,
            amount,
            msg.sender,
            expiresAt
        );
    }
    
    /**
     * @notice Release payment after successful fiat settlement (admin only)
     * @param orderId Order to release
     * @dev For payWithFee payments, fee already taken. For legacy pay(), no additional fee.
     */
    function release(bytes32 orderId) external onlyOwner nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Payment not locked");
        
        // Update status
        payment.status = PaymentStatus.RELEASED;
        
        // Transfer merchant amount to owner (platform wallet for CEX conversion)
        // Fee was already taken at payment time for payWithFee()
        lskToken.safeTransfer(owner(), payment.merchantAmount);
        
        emit PaymentReleased(orderId, payment.merchantAmount);
    }
    
    /**
     * @notice Refund payment to buyer (merchant amount only, admin fee non-refundable)
     * @param orderId Order to refund
     * @param reason Reason for refund
     */
    function refund(bytes32 orderId, string calldata reason) external onlyOwner nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Payment not locked");
        
        // Update status
        payment.status = PaymentStatus.REFUNDED;
        
        // Return merchant amount to buyer (admin fee is non-refundable)
        lskToken.safeTransfer(payment.buyer, payment.merchantAmount);
        
        emit PaymentRefunded(orderId, payment.merchantAmount, reason);
    }
    
    /**
     * @notice Allow buyer to claim refund after expiration
     * @param orderId Order to claim refund for
     */
    function claimExpiredRefund(bytes32 orderId) external nonReentrant {
        Payment storage payment = payments[orderId];
        require(payment.status == PaymentStatus.LOCKED, "Payment not locked");
        require(payment.buyer == msg.sender, "Not the buyer");
        require(block.timestamp > payment.expiresAt, "Payment not expired");
        
        // Update status
        payment.status = PaymentStatus.REFUNDED;
        
        // Return merchant amount to buyer (admin fee is non-refundable)
        lskToken.safeTransfer(payment.buyer, payment.merchantAmount);
        
        emit PaymentRefunded(orderId, payment.merchantAmount, "Expired - buyer claimed");
    }

    // ============ View Functions ============
    
    /**
     * @notice Get payment details (extended with fee info)
     */
    function getPayment(bytes32 orderId) external view returns (
        string memory merchantId,
        address buyer,
        uint256 merchantAmount,
        uint256 adminFee,
        uint256 totalPaid,
        uint256 lockedAt,
        uint256 expiresAt,
        PaymentStatus status
    ) {
        Payment memory p = payments[orderId];
        return (p.merchantId, p.buyer, p.merchantAmount, p.adminFee, p.totalPaid, p.lockedAt, p.expiresAt, p.status);
    }
    
    /**
     * @notice Check if order exists
     */
    function orderExists(bytes32 orderId) external view returns (bool) {
        return payments[orderId].status != PaymentStatus.NONE;
    }
    
    /**
     * @notice Get contract LSK balance (locked for merchants)
     */
    function getLockedBalance() external view returns (uint256) {
        return lskToken.balanceOf(address(this));
    }
    
    /**
     * @notice Get admin fee statistics
     */
    function getFeeStats() external view returns (
        uint256 totalFees,
        uint256 totalVolume,
        address adminWallet,
        uint256 feePercent
    ) {
        return (totalFeesCollected, totalMerchantVolume, feeCollector, platformFeePercent);
    }

    // ============ Admin Functions ============
    
    /**
     * @notice Update payment timeout
     */
    function setPaymentTimeout(uint256 _timeout) external onlyOwner {
        require(_timeout >= 5 minutes, "Timeout too short");
        require(_timeout <= 24 hours, "Timeout too long");
        paymentTimeout = _timeout;
    }
    
    /**
     * @notice Update platform fee (in basis points, 100 = 1%)
     */
    function setPlatformFee(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 500, "Fee too high (max 5%)");
        platformFeePercent = _feePercent;
    }
    
    /**
     * @notice Update fee collector address
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }
    
    /**
     * @notice Emergency withdrawal (only for stuck funds, not locked payments)
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(lskToken), "Cannot withdraw LSK directly");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
