// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleSplitBill
 * @notice Simple split bill escrow - anyone can create bills, no roles required
 */
contract SimpleSplitBill is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum BillStatus { Active, Completed, Cancelled }
    enum ParticipantStatus { Pending, Paid }

    struct Participant {
        address wallet;
        uint256 amountDue;
        uint256 amountPaid;
        ParticipantStatus status;
        uint256 paidAt;
    }

    struct Bill {
        bytes32 billId;
        address creator;
        string description;
        uint256 totalAmount;
        uint256 collectedAmount;
        uint256 createdAt;
        uint256 deadline;
        BillStatus status;
        uint8 participantCount;
        uint8 paidCount;
    }

    // Storage
    mapping(bytes32 => Bill) public bills;
    mapping(bytes32 => Participant[]) public billParticipants;
    mapping(address => bytes32[]) public userBills;      // Bills created by user
    mapping(address => bytes32[]) public userInvitations; // Bills user is invited to

    IERC20 public immutable paymentToken;

    // Events
    event BillCreated(bytes32 indexed billId, address indexed creator, uint256 totalAmount, uint8 participantCount);
    event PaymentReceived(bytes32 indexed billId, address indexed payer, uint256 amount);
    event BillCompleted(bytes32 indexed billId, address indexed creator, uint256 totalAmount);
    event BillCancelled(bytes32 indexed billId, address indexed creator);

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @notice Create a new split bill - anyone can call this
     */
    function createBill(
        bytes32 billId,
        string calldata description,
        address[] calldata participantAddresses,
        uint256[] calldata participantAmounts,
        uint256 deadline
    ) external {
        require(bills[billId].createdAt == 0, "Bill already exists");
        require(participantAddresses.length > 0, "No participants");
        require(participantAddresses.length == participantAmounts.length, "Length mismatch");
        require(deadline > block.timestamp, "Invalid deadline");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < participantAmounts.length; i++) {
            require(participantAmounts[i] > 0, "Amount must be > 0");
            require(participantAddresses[i] != address(0), "Invalid address");
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
            status: BillStatus.Active,
            participantCount: uint8(participantAddresses.length),
            paidCount: 0
        });

        // Add participants
        for (uint256 i = 0; i < participantAddresses.length; i++) {
            billParticipants[billId].push(Participant({
                wallet: participantAddresses[i],
                amountDue: participantAmounts[i],
                amountPaid: 0,
                status: ParticipantStatus.Pending,
                paidAt: 0
            }));
            
            // Add to user's invitations
            userInvitations[participantAddresses[i]].push(billId);
        }

        // Add to creator's bills
        userBills[msg.sender].push(billId);

        emit BillCreated(billId, msg.sender, totalAmount, uint8(participantAddresses.length));
    }

    /**
     * @notice Pay your share of the bill
     */
    function payShare(bytes32 billId) external nonReentrant {
        Bill storage bill = bills[billId];
        require(bill.createdAt > 0, "Bill not found");
        require(bill.status == BillStatus.Active, "Bill not active");
        require(block.timestamp <= bill.deadline, "Bill expired");

        // Find participant
        Participant[] storage participants = billParticipants[billId];
        int256 participantIndex = -1;
        
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].wallet == msg.sender) {
                participantIndex = int256(i);
                break;
            }
        }
        
        require(participantIndex >= 0, "Not a participant");
        Participant storage participant = participants[uint256(participantIndex)];
        require(participant.status == ParticipantStatus.Pending, "Already paid");

        uint256 amount = participant.amountDue;
        
        // Transfer tokens from payer to this contract
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update participant
        participant.amountPaid = amount;
        participant.status = ParticipantStatus.Paid;
        participant.paidAt = block.timestamp;

        // Update bill
        bill.collectedAmount += amount;
        bill.paidCount++;

        emit PaymentReceived(billId, msg.sender, amount);

        // Check if all paid - transfer to creator
        if (bill.paidCount == bill.participantCount) {
            bill.status = BillStatus.Completed;
            paymentToken.safeTransfer(bill.creator, bill.collectedAmount);
            emit BillCompleted(billId, bill.creator, bill.collectedAmount);
        }
    }

    /**
     * @notice Cancel bill (only creator, only if no payments yet)
     */
    function cancelBill(bytes32 billId) external {
        Bill storage bill = bills[billId];
        require(bill.createdAt > 0, "Bill not found");
        require(bill.creator == msg.sender, "Not creator");
        require(bill.status == BillStatus.Active, "Bill not active");
        require(bill.paidCount == 0, "Has payments");

        bill.status = BillStatus.Cancelled;
        emit BillCancelled(billId, msg.sender);
    }

    // ============ VIEW FUNCTIONS ============

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
        bool isParticipant,
        uint256 amountDue,
        uint256 amountPaid,
        bool hasPaid
    ) {
        Participant[] storage participants = billParticipants[billId];
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].wallet == user) {
                return (
                    true,
                    participants[i].amountDue,
                    participants[i].amountPaid,
                    participants[i].status == ParticipantStatus.Paid
                );
            }
        }
        return (false, 0, 0, false);
    }
}
