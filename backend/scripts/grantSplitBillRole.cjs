/**
 * Grant OPERATOR_ROLE on WaltSplitBillEscrow contract
 * Run: node scripts/grantSplitBillRole.cjs <WALLET_ADDRESS>
 */

const { ethers } = require('ethers');
require('dotenv').config();

const SPLIT_BILL_ESCROW_ADDRESS = '0xb7338a31BaE3b39170Cde6044695c444fc78E5F8';
const LISK_SEPOLIA_RPC = 'https://rpc.sepolia-api.lisk.com';

// Role hashes
const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE'));
const DEFAULT_ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000';

const ABI = [
  'function grantRole(bytes32 role, address account) external',
  'function hasRole(bytes32 role, address account) view returns (bool)',
  'function getRoleAdmin(bytes32 role) view returns (bytes32)'
];

async function main() {
  const walletToGrant = process.argv[2];
  
  if (!walletToGrant) {
    console.log('Usage: node scripts/grantSplitBillRole.cjs <WALLET_ADDRESS>');
    console.log('Example: node scripts/grantSplitBillRole.cjs 0x91A1Dc9CEf03BB67DfB181eed683d5Dd94244AAC');
    process.exit(1);
  }

  // Admin private key (the deployer of the contract)
  const adminPrivateKey = process.env.ADMIN_PRIVATE_KEY || process.env.PRIVATE_KEY;
  
  if (!adminPrivateKey) {
    console.error('ERROR: Set ADMIN_PRIVATE_KEY or PRIVATE_KEY in .env file');
    console.log('This should be the private key of the contract deployer/admin');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(LISK_SEPOLIA_RPC);
  const adminWallet = new ethers.Wallet(adminPrivateKey, provider);
  const contract = new ethers.Contract(SPLIT_BILL_ESCROW_ADDRESS, ABI, adminWallet);

  console.log('=== Grant OPERATOR_ROLE on WaltSplitBillEscrow ===');
  console.log('Contract:', SPLIT_BILL_ESCROW_ADDRESS);
  console.log('Admin wallet:', adminWallet.address);
  console.log('Target wallet:', walletToGrant);
  console.log('OPERATOR_ROLE:', OPERATOR_ROLE);
  console.log('');

  // Check if admin has DEFAULT_ADMIN_ROLE
  const adminHasRole = await contract.hasRole(DEFAULT_ADMIN_ROLE, adminWallet.address);
  console.log('Admin has DEFAULT_ADMIN_ROLE:', adminHasRole);

  if (!adminHasRole) {
    console.error('ERROR: Admin wallet does not have DEFAULT_ADMIN_ROLE');
    console.log('Make sure you are using the deployer wallet private key');
    process.exit(1);
  }

  // Check if target already has OPERATOR_ROLE
  const alreadyHasRole = await contract.hasRole(OPERATOR_ROLE, walletToGrant);
  if (alreadyHasRole) {
    console.log('✅ Target wallet already has OPERATOR_ROLE!');
    process.exit(0);
  }

  // Grant the role
  console.log('Granting OPERATOR_ROLE...');
  const tx = await contract.grantRole(OPERATOR_ROLE, walletToGrant);
  console.log('TX Hash:', tx.hash);
  
  await tx.wait();
  console.log('✅ OPERATOR_ROLE granted successfully!');
  
  // Verify
  const hasRoleNow = await contract.hasRole(OPERATOR_ROLE, walletToGrant);
  console.log('Verification - has OPERATOR_ROLE:', hasRoleNow);
}

main().catch(console.error);
