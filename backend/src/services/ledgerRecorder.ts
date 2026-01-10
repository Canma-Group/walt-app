import { ethers } from "ethers";

const LISK_SEPOLIA_RPC = "https://rpc.sepolia-api.lisk.com";

// Simplified ABI for event-only ledger
const LEDGER_ABI = [
  "function recordDeposit(address user, string token, string sourceChain, uint256 amount, string sourceTxHash) external",
  "event DepositRecorded(address indexed user, string token, string sourceChain, uint256 amount, string sourceTxHash, uint256 timestamp)"
];

let provider: ethers.JsonRpcProvider;
let wallet: ethers.Wallet | null = null;
let contract: ethers.Contract | null = null;

export function initLedgerRecorder(privateKey: string, contractAddress: string): void {
  provider = new ethers.JsonRpcProvider(LISK_SEPOLIA_RPC);
  wallet = new ethers.Wallet(privateKey, provider);
  contract = new ethers.Contract(contractAddress, LEDGER_ABI, wallet);
  console.log("[LedgerRecorder] Initialized with address:", wallet.address);
}

export interface DepositRecord {
  userAddress: string;
  tokenSymbol: string;
  sourceChain: string;
  amount: string; // in wei
  sourceTxHash: string;
}

export async function recordDepositOnLisk(deposit: DepositRecord): Promise<string | null> {
  if (!contract || !wallet) {
    console.error("[LedgerRecorder] Not initialized. Call initLedgerRecorder first.");
    return null;
  }

  try {
    console.log("[LedgerRecorder] Recording deposit:", deposit);
    
    const tx = await contract.recordDeposit(
      deposit.userAddress,
      deposit.tokenSymbol,
      deposit.sourceChain,
      deposit.amount,
      deposit.sourceTxHash
    );
    
    console.log("[LedgerRecorder] Tx sent:", tx.hash);
    const receipt = await tx.wait();
    console.log("[LedgerRecorder] Tx confirmed in block:", receipt.blockNumber);
    
    return tx.hash;
  } catch (e: unknown) {
    const error = e as Error;
    console.error("[LedgerRecorder] Error recording deposit:", error.message);
    return null;
  }
}

export async function checkLiskBalance(): Promise<string> {
  if (!wallet) return "0";
  const balance = await provider.getBalance(wallet.address);
  return ethers.formatEther(balance);
}

export function getRecorderAddress(): string | null {
  return wallet?.address || null;
}
