// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SplitBillWithFee
 * @notice Split bill escrow with hybrid fee scheme: Max(0.1 LSK, 1% of total)
 * @dev Fee is deducted when funds are released to creator
 */
contract SplitBillWithFee is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Fee configuration
    uint256 public constant FEE_PERCENTAGE = 100; // 1% = 100 basis points (out of 10000)
    uint256 public constant MIN_FEE = 0.1 ether;  // 0.1 LSK minimum fee
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    address public feeCollector;
    IERC20 public immutable paymentToken;

    enum BillStatus { Active, Completed, Cancelled }
    enum ParticipantStatus { Pending, Paid }

    struct Bill {
        bytes32 billId;
        address creator;
        string description;
        uint256 totalAmount;
        uint256 collectedAmount;
        uint256 createdAt;
        uint256 deadline;
        uint8 status;
        uint8 participantCount;
        uint8 paidCount;
    }

    struct Participant {
        address wallet;
        uint256 amountDue;
        uint256 amountPaid;
        uint8 status;
        uint256 paidAt;
    }

    // Storage
    mapping(bytes32 => Bill) public bills;
    mapping(bytes32 => Participant[]) public billParticipants;
    mapping(bytes32 => mapping(address => uint256)) public participantIndex;
    mapping(bytes32 => mapping(address => bool)) public isParticipant;
    mapping(address => bytes32[]) public userBills;
    mapping(address => bytes32[]) public userInvitations;

    // Events
    event BillCreated(bytes32 indexed billId, address indexed creator, uint256 totalAmount, uint256 participantCount);
    event SharePaid(bytes32 indexed billId, address indexed payer, uint256 amount);
    event BillCompleted(bytes32 indexed billId, address indexed creator, uint256 totalAmount, uint256 feeAmount);
    event BillCancelled(bytes32 indexed billId, address indexed creator);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    constructor(address _paymentToken, address _feeCollector) {
        require(_paymentToken != address(0), "Invalid token");
        require(_feeCollector != address(0), "Invalid fee collector");
        paymentToken = IERC20(_paymentToken);
        feeCollector = _feeCollector;
    }

    /**
     * @notice Calculate platform fee using hybrid scheme: Max(0.1 LSK, 1% of total)
     */
    function calculateFee(uint256 amount) public pure returns (uint256) {
        uint256 percentageFee = (amount * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        return percentageFee > MIN_FEE ? percentageFee : MIN_FEE;
    }

    /**
     * @notice Create a new split bill - anyone can create
     */
    function createBill(
        bytes32 billId,
        string calldata description,
        address[] calldata participantAddresses,
        uint256[] calldata participantAmounts,
        uint256 deadline
    ) external {
        require(bills[billId].creator == address(0), "Bill already exists");
        require(participantAddresses.length > 0, "No participants");
        require(participantAddresses.length == participantAmounts.length, "Length mismatch");
        require(deadline > block.timestamp, "Invalid deadline");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < participantAmounts.length; i++) {
            require(participantAmounts[i] > 0, "Invalid amount");
            require(participantAddresses[i] != address(0), "Invalid address");
            totalAmount += participantAmounts[i];
        }

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

        userBills[msg.sender].push(billId);

        emit BillCreated(billId, msg.sender, totalAmount, participantAddresses.length);
    }

    /**
     * @notice Pay your share of the bill
     */
    function payShare(bytes32 billId) external nonReentrant {
        Bill storage bill = bills[billId];
        require(bill.creator != address(0), "Bill not found");
        require(bill.status == uint8(BillStatus.Active), "Bill not active");
        require(isParticipant[billId][msg.sender], "Not a participant");

        uint256 idx = participantIndex[billId][msg.sender];
        Participant storage participant = billParticipants[billId][idx];
        require(participant.status == uint8(ParticipantStatus.Pending), "Already paid");

        uint256 amount = participant.amountDue;
        
        // Transfer tokens from payer to this contract
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        participant.amountPaid = amount;
        participant.status = uint8(ParticipantStatus.Paid);
        participant.paidAt = block.timestamp;

        bill.collectedAmount += amount;
        bill.paidCount++;

        emit SharePaid(billId, msg.sender, amount);

        // Auto-complete if all participants have paid
        if (bill.paidCount == bill.participantCount) {
            _completeBill(billId);
        }
    }

    /**
     * @notice Internal function to complete bill and release funds
     */
    function _completeBill(bytes32 billId) internal {
        Bill storage bill = bills[billId];
        bill.status = uint8(BillStatus.Completed);

        uint256 totalCollected = bill.collectedAmount;
        uint256 fee = calculateFee(totalCollected);
        uint256 creatorAmount = totalCollected - fee;

        // Transfer fee to fee collector (hot wallet)
        paymentToken.safeTransfer(feeCollector, fee);

        // Transfer remaining to creator
        paymentToken.safeTransfer(bill.creator, creatorAmount);

        emit BillCompleted(billId, bill.creator, creatorAmount, fee);
    }

    /**
     * @notice Cancel bill and refund participants (only creator)
     */
    function cancelBill(bytes32 billId) external nonReentrant {
        Bill storage bill = bills[billId];
        require(bill.creator == msg.sender, "Not creator");
        require(bill.status == uint8(BillStatus.Active), "Bill not active");

        bill.status = uint8(BillStatus.Cancelled);

        // Refund all paid participants
        for (uint256 i = 0; i < billParticipants[billId].length; i++) {
            Participant storage p = billParticipants[billId][i];
            if (p.amountPaid > 0) {
                paymentToken.safeTransfer(p.wallet, p.amountPaid);
            }
        }

        emit BillCancelled(billId, msg.sender);
    }

    // ============ View Functions ============

    function getBill(bytes32 billId) external view returns (Bill memory) {
        return bills[billId];
    }

    function getBillParticipants(bytes32 billId) external view returns (Participant[] memory) {
        return billParticipants[billId];
    }

    function getUserBills(address user) external view returns (bytes32[] memory) {
        return userBills[user];
    }

    function getUserInvitations(address user) external view returns (bytes32[] memory) {
        return userInvitations[user];
    }

    function getParticipantStatus(bytes32 billId, address user) external view returns (
        bool _isParticipant,
        uint256 amountDue,
        uint256 amountPaid,
        bool hasPaid
    ) {
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
     */
    function estimateFee(uint256 billAmount) external pure returns (uint256) {
        return calculateFee(billAmount);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update fee collector address (only current fee collector can change)
     */
    function setFeeCollector(address newCollector) external {
        require(msg.sender == feeCollector, "Not authorized");
        require(newCollector != address(0), "Invalid address");
        emit FeeCollectorUpdated(feeCollector, newCollector);
        feeCollector = newCollector;
    }
}
