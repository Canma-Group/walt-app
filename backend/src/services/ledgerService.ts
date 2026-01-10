import {ethers} from "ethers";
import {liskProvider, getHotWallet} from "../config/lisk";
import * as dotenv from "dotenv";

dotenv.config();

// CrossChainLedger Contract ABI (minimal for interaction)
const LEDGER_ABI = [
  "function recordDeposit(address user, uint256 sourceChainId, address token, uint256 amount, bytes32 sourceTxHash) external",
  "function recordDepositsBatch(address[] users, uint256[] sourceChainIds, address[] tokens, uint256[] amounts, bytes32[] sourceTxHashes) external",
  "function recordWithdrawal(address user, uint256 chainId, address token, uint256 amount, string reason) external",
  "function getBalance(address user, uint256 chainId, address token) view returns (uint256)",
  "function isTxProcessed(uint256 chainId, bytes32 txHash) view returns (bool)",
  "function getTokenInfo(uint256 chainId, address token) view returns (string symbol, string name, uint8 decimals, bool active)",
  "function balances(address, uint256, address) view returns (uint256)",
  "event DepositRecorded(address indexed user, uint256 indexed sourceChainId, address indexed token, uint256 amount, bytes32 sourceTxHash, uint256 timestamp)",
];

// Contract address - will be set after deployment
const LEDGER_CONTRACT_ADDRESS = process.env.LEDGER_CONTRACT_ADDRESS || "";

let ledgerContract: ethers.Contract | null = null;

/**
 * Get Ledger Contract instance (read-only)
 */
export const getLedgerContract = (): ethers.Contract => {
  if (!LEDGER_CONTRACT_ADDRESS) {
    throw new Error("LEDGER_CONTRACT_ADDRESS not configured");
  }
  
  if (!ledgerContract) {
    ledgerContract = new ethers.Contract(
      LEDGER_CONTRACT_ADDRESS,
      LEDGER_ABI,
      liskProvider
    );
  }
  
  return ledgerContract;
};

/**
 * Get Ledger Contract with signer (for write operations)
 */
export const getLedgerContractWithSigner = (): ethers.Contract => {
  const contract = getLedgerContract();
  const hotWallet = getHotWallet();
  return contract.connect(hotWallet) as ethers.Contract;
};

/**
 * Record a deposit from another chain to the Lisk ledger
 */
export const recordDeposit = async (
  userAddress: string,
  sourceChainId: number,
  tokenAddress: string, // address(0) for native token
  amount: string, // in wei
  sourceTxHash: string
): Promise<string> => {
  const contract = getLedgerContractWithSigner();
  
  // Convert txHash to bytes32
  const txHashBytes32 = ethers.zeroPadValue(sourceTxHash, 32);
  
  const tx = await contract.recordDeposit(
    userAddress,
    sourceChainId,
    tokenAddress,
    amount,
    txHashBytes32
  );
  
  const receipt = await tx.wait();
  console.log(`Deposit recorded on Lisk. TxHash: ${receipt.hash}`);
  
  return receipt.hash;
};

/**
 * Check if a transaction has already been processed
 */
export const isTxProcessed = async (
  chainId: number,
  txHash: string
): Promise<boolean> => {
  const contract = getLedgerContract();
  const txHashBytes32 = ethers.zeroPadValue(txHash, 32);
  return await contract.isTxProcessed(chainId, txHashBytes32);
};

/**
 * Get user's ledger balance for a specific chain and token
 */
export const getLedgerBalance = async (
  userAddress: string,
  chainId: number,
  tokenAddress: string = "0x0000000000000000000000000000000000000000"
): Promise<string> => {
  const contract = getLedgerContract();
  const balance = await contract.getBalance(userAddress, chainId, tokenAddress);
  return ethers.formatEther(balance);
};

/**
 * Get all ledger balances for a user across supported chains
 */
export const getAllLedgerBalances = async (
  userAddress: string
): Promise<Array<{
  chainId: number;
  chainName: string;
  token: string;
  symbol: string;
  balance: string;
}>> => {
  const contract = getLedgerContract();
  
  // Supported chains and their native tokens
  const chains = [
    {chainId: 137, name: "Polygon", token: "0x0000000000000000000000000000000000000000", symbol: "POL"},
    {chainId: 1, name: "Ethereum", token: "0x0000000000000000000000000000000000000000", symbol: "ETH"},
    {chainId: 11155111, name: "Sepolia", token: "0x0000000000000000000000000000000000000000", symbol: "ETH"},
  ];
  
  const balances = [];
  
  for (const chain of chains) {
    try {
      const balance = await contract.getBalance(userAddress, chain.chainId, chain.token);
      const formattedBalance = ethers.formatEther(balance);
      
      if (parseFloat(formattedBalance) > 0) {
        balances.push({
          chainId: chain.chainId,
          chainName: chain.name,
          token: chain.token,
          symbol: chain.symbol,
          balance: formattedBalance,
        });
      }
    } catch (e) {
      console.error(`Error fetching balance for chain ${chain.chainId}:`, e);
    }
  }
  
  return balances;
};

/**
 * Get token info from the ledger
 */
export const getTokenInfo = async (
  chainId: number,
  tokenAddress: string
): Promise<{symbol: string; name: string; decimals: number; active: boolean}> => {
  const contract = getLedgerContract();
  const [symbol, name, decimals, active] = await contract.getTokenInfo(chainId, tokenAddress);
  return {symbol, name, decimals, active};
};

/**
 * Manual deposit recording (for API endpoint)
 */
export const manualRecordDeposit = async (
  userAddress: string,
  chainId: number,
  tokenAddress: string,
  amount: string,
  txHash: string
): Promise<string> => {
  // Check if already processed
  const alreadyProcessed = await isTxProcessed(chainId, txHash);
  if (alreadyProcessed) {
    throw new Error("Transaction already processed");
  }
  
  // Record to ledger
  const liskTxHash = await recordDeposit(
    userAddress,
    chainId,
    tokenAddress,
    amount,
    txHash
  );
  
  return liskTxHash;
};;
