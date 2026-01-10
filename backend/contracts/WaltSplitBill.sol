// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WaltSplitBill
 * @author Walt Banking DApp Team
 * @notice Decentralized split bill escrow system with transparent fee mechanism
 * @dev Implements a trustless escrow for splitting bills among multiple participants
 * 
 * ██╗    ██╗ █████╗ ██╗  ████████╗    ███████╗██████╗ ██╗     ██╗████████╗
 * ██║    ██║██╔══██╗██║  ╚══██╔══╝    ██╔════╝██╔══██╗██║     ██║╚══██╔══╝
 * ██║ █╗ ██║███████║██║     ██║       ███████╗██████╔╝██║     ██║   ██║   
 * ██║███╗██║██╔══██║██║     ██║       ╚════██║██╔═══╝ ██║     ██║   ██║   
 * ╚███╔███╔╝██║  ██║███████╗██║       ███████║██║     ███████╗██║   ██║   
 *  ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚═╝       ╚══════╝╚═╝     ╚══════╝╚═╝   ╚═╝   
 * 
 * KEY FEATURES:
 * - Trustless escrow: Funds held securely until all participants pay
 * - Transparent fees: Hybrid fee model (Max of minimum fee or percentage)
 * - Gas sponsorship compatible: Designed to work with off-chain gas sponsorship
 * - Auto-completion: Automatic fund release when all shares are paid
 * - Refund mechanism: Creator can cancel and refund participants
 * - Event-driven: Comprehensive events for off-chain tracking
 * 
 * SECURITY FEATURES:
 * - ReentrancyGuard: Protection against reentrancy attacks
 * - Pausable: Emergency pause functionality
 * - SafeERC20: Safe token transfer operations
 * - Input validation: Comprehensive parameter validation
 * 
 * FEE MODEL:
 * - Hybrid scheme: Max(MIN_FEE, amount * FEE_PERCENTAGE / FEE_DENOMINATOR)
 * - Default: Max(0.1 LSK, 1% of total collected)
 * - Fee deducted only upon successful bill completion
 * - Transparent: Users can calculate exact fee before participating
 */
contract WaltSplitBill is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    /// @notice Platform fee percentage in basis points (100 = 1%)
    uint256 public constant FEE_PERCENTAGE = 100;
    
    /// @notice Minimum platform fee (0.1 token with 18 decimals)
    uint256 public constant MIN_FEE = 0.1 ether;
    
    /// @notice Fee calculation denominator (10000 = 100%)
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    /// @notice Maximum participants per bill (gas optimization)
    uint256 public constant MAX_PARTICIPANTS = 50;
    
    /// @notice Maximum bill duration (365 days)
    uint256 public constant MAX_DEADLINE_DURATION = 365 days;

    // ============ Immutables ============
    
    /// @notice ERC20 token used for payments (LSK)
    IERC20 public immutable paymentToken;
    
    /// @notice Contract deployment timestamp
    uint256 public immutable deployedAt;

    // ============ State Variables ============
    
    /// @notice Address that receives platform fees
    address public feeCollector;
    
    /// @notice Contract owner for admin functions
    address public owner;
    
    /// @notice Total fees collected since deployment
    uint256 public totalFeesCollected;
    
    /// @notice Total volume processed since deployment
    uint256 public totalVolumeProcessed;
    
    /// @notice Total bills created
    uint256 public totalBillsCreated;
    
    /// @notice Total bills completed successfully
    uint256 public totalBillsCompleted;

    // ============ Enums ============
    
    /// @notice Bill lifecycle status
    enum BillStatus { 
        Active,     // 0: Bill is active and accepting payments
        Completed,  // 1: All participants paid, funds released
        Cancelled,  // 2: Creator cancelled, participants refunded
        Expired     // 3: Deadline passed without completion
    }
    
    /// @notice Individual participant payment status
    enum ParticipantStatus { 
        Pending,    // 0: Awaiting payment
        Paid        // 1: Payment received
    }

    // ============ Structs ============
    
    /**
     * @notice Bill data structure
     * @dev Optimized for storage efficiency using appropriate data types
     */
    struct Bill {
        bytes32 billId;           // Unique identifier (32 bytes)
        address creator;          // Bill creator address
        string description;       // Human-readable description
        uint256 totalAmount;      // Sum of all participant amounts
        uint256 collectedAmount;  // Amount collected so far
        uint256 createdAt;        // Creation timestamp
        uint256 deadline;         // Payment deadline timestamp
        uint8 status;             // BillStatus enum
        uint8 participantCount;   // Number of participants
        uint8 paidCount;          // Number of participants who paid
    }

    /**
     * @notice Participant data structure
     * @dev Tracks individual payment obligations and status
     */
    struct Participant {
        address wallet;           // Participant wallet address
        uint256 amountDue;        // Amount this participant owes
        uint256 amountPaid;       // Amount actually paid
        uint8 status;             // ParticipantStatus enum
        uint256 paidAt;           // Payment timestamp (0 if not paid)
    }

    /**
     * @notice Payment breakdown for transparency
     * @dev Returned by getPaymentBreakdown() for UI display
     */
    struct PaymentBreakdown {
        uint256 shareAmount;      // Base amount participant owes
        uint256 platformFee;      // Platform fee (proportional)
        uint256 totalToPay;       // Total amount to pay (same as shareAmount)
        uint256 estimatedCreatorReceives; // What creator will receive after fees
    }

    // ============ Mappings ============
    
    /// @notice Bill ID => Bill data
    mapping(bytes32 => Bill) public bills;
    
    /// @notice Bill ID => Array of participants
    mapping(bytes32 => Participant[]) public billParticipants;
    
    /// @notice Bill ID => Participant address => Index in participants array
    mapping(bytes32 => mapping(address => uint256)) public participantIndex;
    
    /// @notice Bill ID => Participant address => Is participant flag
    mapping(bytes32 => mapping(address => bool)) public isParticipant;
    
    /// @notice User address => Array of bill IDs they created
    mapping(address => bytes32[]) public userCreatedBills;
    
    /// @notice User address => Array of bill IDs they're invited to
    mapping(address => bytes32[]) public userInvitations;

    // ============ Events ============
    
    /**
     * @notice Emitted when a new bill is created
     * @param billId Unique bill identifier
     * @param creator Address of bill creator
     * @param description Bill description
     * @param totalAmount Total bill amount
     * @param participantCount Number of participants
     * @param deadline Payment deadline
     */
    event BillCreated(
        bytes32 indexed billId,
        address indexed creator,
        string description,
        uint256 totalAmount,
        uint256 participantCount,
        uint256 deadline
    );

    /**
     * @notice Emitted when a participant pays their share
     * @param billId Bill identifier
     * @param payer Address of payer
     * @param amount Amount paid
     * @param remainingParticipants Number of participants yet to pay
     */
    event SharePaid(
        bytes32 indexed billId,
        address indexed payer,
        uint256 amount,
        uint256 remainingParticipants
    );

    /**
     * @notice Emitted when bill is completed and funds released
     * @param billId Bill identifier
     * @param creator Address of creator receiving funds
     * @param creatorAmount Amount sent to creator (after fee)
     * @param platformFee Fee collected by platform
     */
    event BillCompleted(
        bytes32 indexed billId,
        address indexed creator,
        uint256 creatorAmount,
        uint256 platformFee
    );

    /**
     * @notice Emitted when bill is cancelled
     * @param billId Bill identifier
     * @param creator Address of creator who cancelled
     * @param refundedAmount Total amount refunded to participants
     */
    event BillCancelled(
        bytes32 indexed billId,
        address indexed creator,
        uint256 refundedAmount
    );

    /**
     * @notice Emitted when fee collector is updated
     * @param oldCollector Previous fee collector address
     * @param newCollector New fee collector address
     */
    event FeeCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );

    /**
     * @notice Emitted when contract ownership is transferred
     * @param previousOwner Previous owner address
     * @param newOwner New owner address
     */
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // ============ Modifiers ============
    
    /// @notice Restricts function to contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "WaltSplitBill: caller is not owner");
        _;
    }

    /// @notice Validates bill exists and is active
    modifier billActive(bytes32 billId) {
        require(bills[billId].creator != address(0), "WaltSplitBill: bill not found");
        require(bills[billId].status == uint8(BillStatus.Active), "WaltSplitBill: bill not active");
        _;
    }

    // ============ Constructor ============
    
    /**
     * @notice Deploy WaltSplitBill contract
     * @param _paymentToken ERC20 token address for payments
     * @param _feeCollector Address to receive platform fees
     */
    constructor(address _paymentToken, address _feeCollector) {
        require(_paymentToken != address(0), "WaltSplitBill: invalid token address");
        require(_feeCollector != address(0), "WaltSplitBill: invalid fee collector");
        
        paymentToken = IERC20(_paymentToken);
        feeCollector = _feeCollector;
        owner = msg.sender;
        deployedAt = block.timestamp;
        
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ============ Core Functions ============

    /**
     * @notice Create a new split bill
     * @dev Anyone can create a bill. Creator is not automatically a participant.
     * @param billId Unique identifier (typically generated off-chain)
     * @param description Human-readable bill description
     * @param participantAddresses Array of participant wallet addresses
     * @param participantAmounts Array of amounts each participant owes
     * @param deadline Unix timestamp for payment deadline
     * 
     * Requirements:
     * - billId must be unique (not used before)
     * - At least 1 participant required
     * - Arrays must have matching lengths
     * - All amounts must be > 0
     * - Deadline must be in the future but within MAX_DEADLINE_DURATION
     * 
     * Emits: BillCreated
     */
    function createBill(
        bytes32 billId,
        string calldata description,
        address[] calldata participantAddresses,
        uint256[] calldata participantAmounts,
        uint256 deadline
    ) external whenNotPaused {
        // Validation
        require(bills[billId].creator == address(0), "WaltSplitBill: bill ID already exists");
        require(participantAddresses.length > 0, "WaltSplitBill: no participants");
        require(participantAddresses.length <= MAX_PARTICIPANTS, "WaltSplitBill: too many participants");
        require(participantAddresses.length == participantAmounts.length, "WaltSplitBill: array length mismatch");
        require(deadline > block.timestamp, "WaltSplitBill: deadline must be in future");
        require(deadline <= block.timestamp + MAX_DEADLINE_DURATION, "WaltSplitBill: deadline too far");
        require(bytes(description).length <= 256, "WaltSplitBill: description too long");

        // Calculate total and validate participants
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < participantAddresses.length; i++) {
            require(participantAddresses[i] != address(0), "WaltSplitBill: invalid participant address");
            require(participantAmounts[i] > 0, "WaltSplitBill: amount must be positive");
            require(!isParticipant[billId][participantAddresses[i]], "WaltSplitBill: duplicate participant");
            totalAmount += participantAmounts[i];
        }

        // Create bill
        bills[billId] = Bill({
            billId: billId,
            creator: msg.sender,
            description: description,
            totalAmount: totalAmount,
            collectedAmount: 0,
            createdAt: block.timestamp,
            deadline: deadline,
            status: uint8(BillStatus.Active),
            participantCount: uint8(participantAddresses.length),
            paidCount: 0
        });

        // Add participants
        for (uint256 i = 0; i < participantAddresses.length; i++) {
            billParticipants[billId].push(Participant({
                wallet: participantAddresses[i],
                amountDue: participantAmounts[i],
                amountPaid: 0,
                status: uint8(ParticipantStatus.Pending),
                paidAt: 0
            }));
            
            participantIndex[billId][participantAddresses[i]] = i;
            isParticipant[billId][participantAddresses[i]] = true;
            userInvitations[participantAddresses[i]].push(billId);
        }

        // Track creator's bills
        userCreatedBills[msg.sender].push(billId);
        totalBillsCreated++;

        emit BillCreated(billId, msg.sender, description, totalAmount, participantAddresses.length, deadline);
    }

    /**
     * @notice Pay your share of a bill
     * @dev Caller must be a participant and have approved token transfer
     * @param billId The bill to pay for
     * 
     * Requirements:
     * - Bill must be active
     * - Caller must be a participant
     * - Caller must not have already paid
     * - Caller must have approved sufficient token allowance
     * 
     * Effects:
     * - Transfers tokens from caller to contract
     * - Updates participant status to Paid
     * - If all participants paid, triggers bill completion
     * 
     * Emits: SharePaid
     * Emits: BillCompleted (if all participants have paid)
     */
    function payShare(bytes32 billId) external nonReentrant whenNotPaused billActive(billId) {
        require(isParticipant[billId][msg.sender], "WaltSplitBill: not a participant");
        
        uint256 idx = participantIndex[billId][msg.sender];
        Participant storage participant = billParticipants[billId][idx];
        
        require(participant.status == uint8(ParticipantStatus.Pending), "WaltSplitBill: already paid");

        uint256 amount = participant.amountDue;
        
        // Transfer tokens from payer to escrow
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update participant record
        participant.amountPaid = amount;
        participant.status = uint8(ParticipantStatus.Paid);
        participant.paidAt = block.timestamp;

        // Update bill totals
        Bill storage bill = bills[billId];
        bill.collectedAmount += amount;
        bill.paidCount++;

        uint256 remaining = bill.participantCount - bill.paidCount;
        emit SharePaid(billId, msg.sender, amount, remaining);

        // Auto-complete if all participants have paid
        if (bill.paidCount == bill.participantCount) {
            _completeBill(billId);
        }
    }

    /**
     * @notice Cancel a bill and refund all participants
     * @dev Only the bill creator can cancel
     * @param billId The bill to cancel
     * 
     * Requirements:
     * - Caller must be the bill creator
     * - Bill must be active
     * 
     * Effects:
     * - Refunds all participants who have paid
     * - Sets bill status to Cancelled
     * 
     * Emits: BillCancelled
     */
    function cancelBill(bytes32 billId) external nonReentrant billActive(billId) {
        Bill storage bill = bills[billId];
        require(bill.creator == msg.sender, "WaltSplitBill: not bill creator");

        bill.status = uint8(BillStatus.Cancelled);
        uint256 totalRefunded = 0;

        // Refund all paid participants
        for (uint256 i = 0; i < billParticipants[billId].length; i++) {
            Participant storage p = billParticipants[billId][i];
            if (p.amountPaid > 0) {
                paymentToken.safeTransfer(p.wallet, p.amountPaid);
                totalRefunded += p.amountPaid;
            }
        }

        emit BillCancelled(billId, msg.sender, totalRefunded);
    }

    // ============ Internal Functions ============

    /**
     * @notice Complete a bill and distribute funds
     * @dev Called automatically when all participants have paid
     * @param billId The bill to complete
     */
    function _completeBill(bytes32 billId) internal {
        Bill storage bill = bills[billId];
        bill.status = uint8(BillStatus.Completed);

        uint256 totalCollected = bill.collectedAmount;
        uint256 fee = calculateFee(totalCollected);
        uint256 creatorAmount = totalCollected - fee;

        // Transfer fee to platform
        if (fee > 0) {
            paymentToken.safeTransfer(feeCollector, fee);
            totalFeesCollected += fee;
        }

        // Transfer remaining to creator
        paymentToken.safeTransfer(bill.creator, creatorAmount);
        
        // Update statistics
        totalVolumeProcessed += totalCollected;
        totalBillsCompleted++;

        emit BillCompleted(billId, bill.creator, creatorAmount, fee);
    }

    // ============ View Functions ============

    /**
     * @notice Calculate platform fee for a given amount
     * @dev Hybrid model: Max(MIN_FEE, amount * FEE_PERCENTAGE / FEE_DENOMINATOR)
     * @param amount The amount to calculate fee for
     * @return fee The calculated fee amount
     */
    function calculateFee(uint256 amount) public pure returns (uint256) {
        uint256 percentageFee = (amount * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        return percentageFee > MIN_FEE ? percentageFee : MIN_FEE;
    }

    /**
     * @notice Get detailed payment breakdown for a participant
     * @dev Used by frontend to display fee transparency before payment
     * @param billId The bill ID
     * @param participant The participant address
     * @return breakdown PaymentBreakdown struct with all fee details
     */
    function getPaymentBreakdown(bytes32 billId, address participant) 
        external 
        view 
        returns (PaymentBreakdown memory breakdown) 
    {
        require(isParticipant[billId][participant], "WaltSplitBill: not a participant");
        
        Bill storage bill = bills[billId];
        uint256 idx = participantIndex[billId][participant];
        Participant storage p = billParticipants[billId][idx];
        
        uint256 shareAmount = p.amountDue;
        uint256 totalBillFee = calculateFee(bill.totalAmount);
        
        // Calculate proportional fee for this participant's share
        uint256 proportionalFee = (totalBillFee * shareAmount) / bill.totalAmount;
        
        breakdown = PaymentBreakdown({
            shareAmount: shareAmount,
            platformFee: proportionalFee,
            totalToPay: shareAmount, // User pays full share, fee deducted from creator
            estimatedCreatorReceives: bill.totalAmount - totalBillFee
        });
    }

    /**
     * @notice Get bill details
     * @param billId The bill ID
     * @return Bill struct
     */
    function getBill(bytes32 billId) external view returns (Bill memory) {
        return bills[billId];
    }

    /**
     * @notice Get all participants for a bill
     * @param billId The bill ID
     * @return Array of Participant structs
     */
    function getBillParticipants(bytes32 billId) external view returns (Participant[] memory) {
        return billParticipants[billId];
    }

    /**
     * @notice Get bills created by a user
     * @param user User address
     * @return Array of bill IDs
     */
    function getUserBills(address user) external view returns (bytes32[] memory) {
        return userCreatedBills[user];
    }

    /**
     * @notice Get invitations for a user
     * @param user User address
     * @return Array of bill IDs
     */
    function getUserInvitations(address user) external view returns (bytes32[] memory) {
        return userInvitations[user];
    }

    /**
     * @notice Get participant status for a specific bill
     * @param billId The bill ID
     * @param user The participant address
     * @return _isParticipant Whether user is a participant
     * @return amountDue Amount the participant owes
     * @return amountPaid Amount already paid
     * @return hasPaid Whether participant has paid
     */
    function getParticipantStatus(bytes32 billId, address user) 
        external 
        view 
        returns (
            bool _isParticipant,
            uint256 amountDue,
            uint256 amountPaid,
            bool hasPaid
        ) 
    {
        _isParticipant = isParticipant[billId][user];
        if (_isParticipant) {
            uint256 idx = participantIndex[billId][user];
            Participant storage p = billParticipants[billId][idx];
            amountDue = p.amountDue;
            amountPaid = p.amountPaid;
            hasPaid = p.status == uint8(ParticipantStatus.Paid);
        }
    }

    /**
     * @notice Estimate fee for a given bill amount
     * @param billAmount Total bill amount
     * @return Calculated fee
     */
    function estimateFee(uint256 billAmount) external pure returns (uint256) {
        return calculateFee(billAmount);
    }

    /**
     * @notice Get contract statistics
     * @return _totalBillsCreated Total bills created
     * @return _totalBillsCompleted Total bills completed
     * @return _totalVolumeProcessed Total volume processed
     * @return _totalFeesCollected Total fees collected
     * @return _contractBalance Current contract token balance
     */
    function getStatistics() 
        external 
        view 
        returns (
            uint256 _totalBillsCreated,
            uint256 _totalBillsCompleted,
            uint256 _totalVolumeProcessed,
            uint256 _totalFeesCollected,
            uint256 _contractBalance
        ) 
    {
        return (
            totalBillsCreated,
            totalBillsCompleted,
            totalVolumeProcessed,
            totalFeesCollected,
            paymentToken.balanceOf(address(this))
        );
    }

    // ============ Admin Functions ============

    /**
     * @notice Update fee collector address
     * @dev Only current fee collector can change
     * @param newCollector New fee collector address
     */
    function setFeeCollector(address newCollector) external {
        require(msg.sender == feeCollector, "WaltSplitBill: not fee collector");
        require(newCollector != address(0), "WaltSplitBill: invalid address");
        
        emit FeeCollectorUpdated(feeCollector, newCollector);
        feeCollector = newCollector;
    }

    /**
     * @notice Transfer contract ownership
     * @dev Only owner can transfer
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "WaltSplitBill: invalid address");
        
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @notice Pause contract (emergency)
     * @dev Only owner can pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     * @dev Only owner can unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens (not escrowed funds)
     * @dev Only owner, only for recovery purposes
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(paymentToken), "WaltSplitBill: cannot withdraw payment token");
        IERC20(token).safeTransfer(owner, amount);
    }
}
