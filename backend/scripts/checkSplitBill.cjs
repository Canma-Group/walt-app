/**
 * Check SimpleSplitBill contract state
 * Run: node scripts/checkSplitBill.cjs <WALLET_ADDRESS>
 */

const { ethers } = require('ethers');
require('dotenv').config();

const CONTRACT_ADDRESS = '0xBaabd80EC0951025DfC96B12519608718B08157E';
const LISK_SEPOLIA_RPC = 'https://rpc.sepolia-api.lisk.com';

const ABI = [
  'function getUserBills(address user) view returns (bytes32[])',
  'function getUserInvitations(address user) view returns (bytes32[])',
  'function getBill(bytes32 billId) view returns (tuple(bytes32 billId, address creator, string description, uint256 totalAmount, uint256 collectedAmount, uint256 createdAt, uint256 deadline, uint8 status, uint8 participantCount, uint8 paidCount))',
  'function getBillParticipants(bytes32 billId) view returns (tuple(address wallet, uint256 amountDue, uint256 amountPaid, uint8 status, uint256 paidAt)[])'
];

async function main() {
  const walletAddress = process.argv[2];
  
  if (!walletAddress) {
    console.log('Usage: node scripts/checkSplitBill.cjs <WALLET_ADDRESS>');
    console.log('Example: node scripts/checkSplitBill.cjs 0x91A1Dc9CEf03BB67DfB181eed683d5Dd94244AAC');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(LISK_SEPOLIA_RPC);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);

  console.log('=== SimpleSplitBill Contract Check ===');
  console.log('Contract:', CONTRACT_ADDRESS);
  console.log('Checking wallet:', walletAddress);
  console.log('');

  // Check bills created by this user
  console.log('--- Bills Created (getUserBills) ---');
  const userBills = await contract.getUserBills(walletAddress);
  console.log('Count:', userBills.length);
  for (const billId of userBills) {
    console.log('  Bill ID:', billId);
    try {
      const bill = await contract.getBill(billId);
      console.log('    Creator:', bill.creator);
      console.log('    Description:', bill.description);
      console.log('    Total:', ethers.formatEther(bill.totalAmount), 'LSK');
      console.log('    Collected:', ethers.formatEther(bill.collectedAmount), 'LSK');
      console.log('    Status:', bill.status);
      console.log('    Participants:', bill.participantCount);
      console.log('    Paid:', bill.paidCount);
      
      const participants = await contract.getBillParticipants(billId);
      console.log('    --- Participants ---');
      for (const p of participants) {
        console.log(`      ${p.wallet}: ${ethers.formatEther(p.amountDue)} LSK (paid: ${p.status === 1n})`);
      }
    } catch (e) {
      console.log('    Error fetching bill:', e.message);
    }
  }

  console.log('');

  // Check invitations for this user
  console.log('--- Invitations (getUserInvitations) ---');
  const invitations = await contract.getUserInvitations(walletAddress);
  console.log('Count:', invitations.length);
  for (const billId of invitations) {
    console.log('  Bill ID:', billId);
    try {
      const bill = await contract.getBill(billId);
      console.log('    Creator:', bill.creator);
      console.log('    Description:', bill.description);
      console.log('    Total:', ethers.formatEther(bill.totalAmount), 'LSK');
    } catch (e) {
      console.log('    Error fetching bill:', e.message);
    }
  }
}

main().catch(console.error);
