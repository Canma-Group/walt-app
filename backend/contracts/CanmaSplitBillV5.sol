// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title waltSplitBillV5
 * @author walt Wallet Team
 * @notice Production-ready split bill smart contract with complete lifecycle management
 * @dev Version 5.0 features:
 *      - Clear state machine (Active, Completed, Cancelled, Expired)
 *      - Creator-only bill creation (creator does NOT pay)
 *      - One-time payment per participant
 *      - Auto-complete when all participants pay
 *      - Pull-based refund after deadline (participants claim themselves)
 *      - Comprehensive events for Web3 tracking
 *      - Admin fee support
 *      - Multi-token support
 */
contract waltSplitBillV5 is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    string public constant VERSION = "5.0.0";
    string public constant NAME = "waltSplitBillV5";
    
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE_BPS = 500; // Max 5% fee
    uint256 public constant MAX_PARTICIPANTS = 50;
    uint256 public constant MIN_DEADLINE_DURATION = 1 minutes; // Changed for testing - revert to 1 hours for production

    // ============ Enums ============

    enum BillStatus {
        Active,     // 0: Bill is active and accepting payments
        Completed,  // 1: All participants paid, funds released to creator
        Cancelled,  // 2: Creator cancelled, participants refunded
        Expired     // 3: Deadline passed, participants can claim refund
    }

    // ============ Structs ============

    struct Participant {
        address wallet;
        uint256 amountDue;
        uint256 amountPaid;
        bool hasPaid;
        bool hasClaimedRefund;
    }

    struct Bill {
        bytes32 billId;
        address creator;
        address paymentToken;
        uint256 totalAmount;
        uint256 amountPerParticipant;
        uint256 deadline;
        uint256 createdAt;
        uint256 completedAt;
        uint256 participantCount;
        uint256 paidCount;
        uint256 totalCollected;
        uint8 status;
        string description;
    }

    // ============ State Variables ============

    /// @notice Fee receiver address
    address public feeReceiver;
    
    /// @notice Admin fee in basis points (default 0.5% = 50 bps)
    uint256 public adminFeeBps = 50;
    
    /// @notice Supported payment tokens
    mapping(address => bool) public supportedTokens;
    
    /// @notice Bill counter for unique IDs
    uint256 public billCounter;
    
    /// @notice All bills by ID
    mapping(bytes32 => Bill) public bills;
    
    /// @notice Participants per bill
    mapping(bytes32 => Participant[]) public billParticipants;
    
    /// @notice Participant index lookup
    mapping(bytes32 => mapping(address => uint256)) public participantIndex;
    
    /// @notice Check if address is participant
    mapping(bytes32 => mapping(address => bool)) public isParticipant;
    
    /// @notice User's bills (as creator)
    mapping(address => bytes32[]) public userCreatedBills;
    
    /// @notice User's bills (as participant)
    mapping(address => bytes32[]) public userParticipatingBills;
    
    /// @notice Total fees collected per token
    mapping(address => uint256) public totalFeesCollected;

    // ============ Events ============

    event BillCreated(
        bytes32 indexed billId,
        address indexed creator,
        address paymentToken,
        uint256 totalAmount,
        uint256 participantCount,
        uint256 deadline,
        string description
    );

    event BillPaid(
        bytes32 indexed billId,
        address indexed participant,
        uint256 amount,
        uint256 paidCount,
        uint256 totalParticipants
    );

    event BillCompleted(
        bytes32 indexed billId,
        address indexed creator,
        uint256 totalAmount,
        uint256 adminFee,
        uint256 timestamp
    );

    event BillCancelled(
        bytes32 indexed billId,
        address indexed creator,
        uint256 refundedAmount,
        uint256 timestamp
    );

    event BillExpired(
        bytes32 indexed billId,
        uint256 timestamp
    );

    event RefundClaimed(
        bytes32 indexed billId,
        address indexed participant,
        uint256 amount,
        uint256 timestamp
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    // ============ Errors ============

    error InvalidAddress();
    error InvalidAmount();
    error InvalidDeadline();
    error InvalidParticipantCount();
    error TokenNotSupported();
    error BillNotFound();
    error BillNotActive();
    error NotParticipant();
    error AlreadyPaid();
    error NotCreator();
    error DeadlineNotPassed();
    error NoRefundAvailable();
    error AlreadyClaimed();
    error CreatorCannotBeParticipant();
    error DuplicateParticipant();

    // ============ Modifiers ============

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    modifier billExists(bytes32 billId) {
        if (bills[billId].creator == address(0)) revert BillNotFound();
        _;
    }

    modifier billActive(bytes32 billId) {
        if (bills[billId].status != uint8(BillStatus.Active)) revert BillNotActive();
        _;
    }

    modifier onlyCreator(bytes32 billId) {
        if (bills[billId].creator != msg.sender) revert NotCreator();
        _;
    }

    modifier onlyParticipant(bytes32 billId) {
        if (!isParticipant[billId][msg.sender]) revert NotParticipant();
        _;
    }

    // ============ Constructor ============

    constructor(address _feeReceiver) Ownable(msg.sender) {
        if (_feeReceiver == address(0)) revert InvalidAddress();
        feeReceiver = _feeReceiver;
    }

    // ============ Core Functions ============

    /**
     * @notice Create a new split bill
     * @dev Creator does NOT pay - only participants pay
     * @param paymentToken Token address for payment
     * @param totalAmount Total bill amount
     * @param deadline Payment deadline timestamp
     * @param participants Array of participant addresses
     * @param description Bill description
     * @return billId Unique bill identifier
     */
    function createBill(
        address paymentToken,
        uint256 totalAmount,
        uint256 deadline,
        address[] calldata participants,
        string calldata description
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (bytes32 billId) 
    {
        // Validations
        if (!supportedTokens[paymentToken]) revert TokenNotSupported();
        if (totalAmount == 0) revert InvalidAmount();
        if (deadline <= block.timestamp + MIN_DEADLINE_DURATION) revert InvalidDeadline();
        if (participants.length == 0 || participants.length > MAX_PARTICIPANTS) revert InvalidParticipantCount();

        // Generate unique bill ID
        billCounter++;
        billId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            billCounter,
            block.chainid
        ));

        // Calculate amount per participant
        uint256 amountPerParticipant = totalAmount / participants.length;

        // Create bill
        bills[billId] = Bill({
            billId: billId,
            creator: msg.sender,
            paymentToken: paymentToken,
            totalAmount: totalAmount,
            amountPerParticipant: amountPerParticipant,
            deadline: deadline,
            createdAt: block.timestamp,
            completedAt: 0,
            participantCount: participants.length,
            paidCount: 0,
            totalCollected: 0,
            status: uint8(BillStatus.Active),
            description: description
        });

        // Add participants
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            
            // Creator cannot be a participant
            if (participant == msg.sender) revert CreatorCannotBeParticipant();
            if (participant == address(0)) revert InvalidAddress();
            
            // Check for duplicates
            if (isParticipant[billId][participant]) revert DuplicateParticipant();
            
            isParticipant[billId][participant] = true;
            participantIndex[billId][participant] = i;
            
            billParticipants[billId].push(Participant({
                wallet: participant,
                amountDue: amountPerParticipant,
                amountPaid: 0,
                hasPaid: false,
                hasClaimedRefund: false
            }));
            
            userParticipatingBills[participant].push(billId);
        }

        userCreatedBills[msg.sender].push(billId);

        emit BillCreated(
            billId,
            msg.sender,
            paymentToken,
            totalAmount,
            participants.length,
            deadline,
            description
        );
    }

    /**
     * @notice Pay your share of a bill
     * @dev One-time payment only. Auto-completes if all paid.
     * @param billId The bill to pay
     */
    function payShare(bytes32 billId) 
        external 
        nonReentrant 
        whenNotPaused
        billExists(billId)
        billActive(billId)
        onlyParticipant(billId)
    {
        Bill storage bill = bills[billId];
        
        // Check deadline
        if (block.timestamp > bill.deadline) {
            bill.status = uint8(BillStatus.Expired);
            emit BillExpired(billId, block.timestamp);
            revert BillNotActive();
        }

        uint256 idx = participantIndex[billId][msg.sender];
        Participant storage participant = billParticipants[billId][idx];

        // Check not already paid
        if (participant.hasPaid) revert AlreadyPaid();

        uint256 paymentAmount = participant.amountDue;

        // Transfer payment from participant to contract
        IERC20(bill.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            paymentAmount
        );

        // Update participant
        participant.amountPaid = paymentAmount;
        participant.hasPaid = true;

        // Update bill
        bill.paidCount++;
        bill.totalCollected += paymentAmount;

        emit BillPaid(
            billId,
            msg.sender,
            paymentAmount,
            bill.paidCount,
            bill.participantCount
        );

        // Auto-complete if all participants paid
        if (bill.paidCount == bill.participantCount) {
            _completeBill(billId);
        }
    }

    /**
     * @notice Cancel a bill (creator only)
     * @dev Refunds all paid participants automatically
     * @param billId The bill to cancel
     */
    function cancelBill(bytes32 billId)
        external
        nonReentrant
        billExists(billId)
        billActive(billId)
        onlyCreator(billId)
    {
        Bill storage bill = bills[billId];
        bill.status = uint8(BillStatus.Cancelled);

        uint256 totalRefunded = 0;

        // Refund all paid participants
        Participant[] storage participants = billParticipants[billId];
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].amountPaid > 0 && !participants[i].hasClaimedRefund) {
                uint256 refundAmount = participants[i].amountPaid;
                participants[i].hasClaimedRefund = true;
                
                IERC20(bill.paymentToken).safeTransfer(
                    participants[i].wallet,
                    refundAmount
                );
                
                totalRefunded += refundAmount;
                
                emit RefundClaimed(
                    billId,
                    participants[i].wallet,
                    refundAmount,
                    block.timestamp
                );
            }
        }

        emit BillCancelled(billId, msg.sender, totalRefunded, block.timestamp);
    }

    /**
     * @notice Claim refund after deadline (pull-based)
     * @dev Participants call this to get their money back after deadline
     * @param billId The expired bill
     */
    function claimRefund(bytes32 billId)
        external
        nonReentrant
        billExists(billId)
        onlyParticipant(billId)
    {
        Bill storage bill = bills[billId];
        
        // Must be past deadline
        if (block.timestamp <= bill.deadline) revert DeadlineNotPassed();
        
        // Mark as expired if still active
        if (bill.status == uint8(BillStatus.Active)) {
            bill.status = uint8(BillStatus.Expired);
            emit BillExpired(billId, block.timestamp);
        }
        
        // Must be Active (just marked expired) or already Expired
        if (bill.status != uint8(BillStatus.Expired)) revert BillNotActive();

        uint256 idx = participantIndex[billId][msg.sender];
        Participant storage participant = billParticipants[billId][idx];

        // Check has payment to refund
        if (participant.amountPaid == 0) revert NoRefundAvailable();
        if (participant.hasClaimedRefund) revert AlreadyClaimed();

        uint256 refundAmount = participant.amountPaid;
        participant.hasClaimedRefund = true;

        IERC20(bill.paymentToken).safeTransfer(msg.sender, refundAmount);

        emit RefundClaimed(billId, msg.sender, refundAmount, block.timestamp);
    }

    // ============ Internal Functions ============

    /**
     * @notice Complete a bill and transfer funds to creator
     * @param billId The bill to complete
     */
    function _completeBill(bytes32 billId) internal {
        Bill storage bill = bills[billId];
        bill.status = uint8(BillStatus.Completed);
        bill.completedAt = block.timestamp;

        uint256 totalAmount = bill.totalCollected;
        uint256 adminFee = (totalAmount * adminFeeBps) / BPS_DENOMINATOR;
        uint256 creatorAmount = totalAmount - adminFee;

        // Transfer admin fee
        if (adminFee > 0) {
            IERC20(bill.paymentToken).safeTransfer(feeReceiver, adminFee);
            totalFeesCollected[bill.paymentToken] += adminFee;
        }

        // Transfer to creator
        IERC20(bill.paymentToken).safeTransfer(bill.creator, creatorAmount);

        emit BillCompleted(billId, bill.creator, creatorAmount, adminFee, block.timestamp);
    }

    // ============ View Functions ============

    /**
     * @notice Get bill details
     * @param billId The bill ID
     * @return bill The bill struct
     */
    function getBill(bytes32 billId) external view returns (Bill memory) {
        return bills[billId];
    }

    /**
     * @notice Get all participants of a bill
     * @param billId The bill ID
     * @return participants Array of participants
     */
    function getBillParticipants(bytes32 billId) 
        external 
        view 
        returns (Participant[] memory) 
    {
        return billParticipants[billId];
    }

    /**
     * @notice Get participant info
     * @param billId The bill ID
     * @param participant Participant address
     * @return info Participant struct
     */
    function getParticipantInfo(bytes32 billId, address participant)
        external
        view
        returns (Participant memory info)
    {
        if (!isParticipant[billId][participant]) revert NotParticipant();
        uint256 idx = participantIndex[billId][participant];
        return billParticipants[billId][idx];
    }

    /**
     * @notice Get bills created by user
     * @param user User address
     * @return billIds Array of bill IDs
     */
    function getUserCreatedBills(address user) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return userCreatedBills[user];
    }

    /**
     * @notice Get bills where user is participant
     * @param user User address
     * @return billIds Array of bill IDs
     */
    function getUserParticipatingBills(address user) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return userParticipatingBills[user];
    }

    /**
     * @notice Check if bill is expired
     * @param billId The bill ID
     * @return expired True if past deadline
     */
    function isBillExpired(bytes32 billId) external view returns (bool) {
        return block.timestamp > bills[billId].deadline;
    }

    /**
     * @notice Get current bill status (with auto-expire check)
     * @param billId The bill ID
     * @return status The current status
     */
    function getBillStatus(bytes32 billId) external view returns (BillStatus) {
        Bill storage bill = bills[billId];
        if (bill.status == uint8(BillStatus.Active) && block.timestamp > bill.deadline) {
            return BillStatus.Expired;
        }
        return BillStatus(bill.status);
    }

    // ============ Admin Functions ============

    /**
     * @notice Add supported payment token
     * @param token Token address
     */
    function addToken(address token) external onlyOwner validAddress(token) {
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    /**
     * @notice Remove supported payment token
     * @param token Token address
     */
    function removeToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    /**
     * @notice Update admin fee
     * @param newFeeBps New fee in basis points
     */
    function updateAdminFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "Fee too high");
        uint256 oldFee = adminFeeBps;
        adminFeeBps = newFeeBps;
        emit FeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @notice Update fee receiver
     * @param newFeeReceiver New receiver address
     */
    function updateFeeReceiver(address newFeeReceiver) 
        external 
        onlyOwner 
        validAddress(newFeeReceiver) 
    {
        address oldReceiver = feeReceiver;
        feeReceiver = newFeeReceiver;
        emit FeeReceiverUpdated(oldReceiver, newFeeReceiver);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token address
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
        }
    }
}
