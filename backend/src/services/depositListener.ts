import {ethers} from "ethers";
import * as admin from "firebase-admin";
import {polygonProvider, POLYGON_CONFIG} from "../config/polygon";
import {recordDeposit, isTxProcessed} from "./ledgerService";

const db = admin.firestore();

// Track processed blocks to avoid reprocessing
let lastProcessedBlock = 0;

interface DepositEvent {
  userAddress: string;
  chainId: number;
  tokenAddress: string;
  amount: string;
  txHash: string;
  blockNumber: number;
  timestamp: number;
}

/**
 * Get list of wallet addresses to monitor from Firestore
 */
const getMonitoredAddresses = async (): Promise<Map<string, string>> => {
  const addressMap = new Map<string, string>(); // address -> userId
  
  // Try both field names (wallet_address and walletAddress)
  const usersSnapshot = await db.collection("users").get();
  
  usersSnapshot.forEach((doc) => {
    const data = doc.data();
    const addr = data.wallet_address || data.walletAddress;
    if (addr) {
      addressMap.set(addr.toLowerCase(), doc.id);
    }
  });
  
  return addressMap;
};

/**
 * Check for new deposits to monitored addresses
 */
export const checkNewDeposits = async (): Promise<DepositEvent[]> => {
  const deposits: DepositEvent[] = [];
  
  try {
    // Get current block
    const currentBlock = await polygonProvider.getBlockNumber();
    
    // If first run, start from current block - 100
    if (lastProcessedBlock === 0) {
      lastProcessedBlock = currentBlock - 100;
    }
    
    // Don't process if no new blocks
    if (currentBlock <= lastProcessedBlock) {
      return deposits;
    }
    
    // Get monitored addresses
    const monitoredAddresses = await getMonitoredAddresses();
    
    if (monitoredAddresses.size === 0) {
      console.log("No addresses to monitor");
      lastProcessedBlock = currentBlock;
      return deposits;
    }
    
    console.log(`Checking blocks ${lastProcessedBlock + 1} to ${currentBlock} for ${monitoredAddresses.size} addresses`);
    
    // Process blocks in chunks to avoid timeout
    const chunkSize = 50;
    
    for (let fromBlock = lastProcessedBlock + 1; fromBlock <= currentBlock; fromBlock += chunkSize) {
      const toBlock = Math.min(fromBlock + chunkSize - 1, currentBlock);
      
      // Check native POL transfers to monitored addresses
      for (const [address, _userId] of monitoredAddresses) {
        try {
          // Get block with transactions
          const block = await polygonProvider.getBlock(toBlock, true);
          
          if (block && block.prefetchedTransactions) {
            for (const tx of block.prefetchedTransactions) {
              if (tx.to?.toLowerCase() === address) {
                // Check if this is a value transfer
                if (tx.value > BigInt(0)) {
                  const deposit: DepositEvent = {
                    userAddress: address,
                    chainId: POLYGON_CONFIG.chainId,
                    tokenAddress: "0x0000000000000000000000000000000000000000", // Native POL
                    amount: tx.value.toString(),
                    txHash: tx.hash,
                    blockNumber: toBlock,
                    timestamp: block.timestamp,
                  };
                  
                  deposits.push(deposit);
                }
              }
            }
          }
        } catch (e) {
          console.error(`Error checking address ${address}:`, e);
        }
      }
    }
    
    lastProcessedBlock = currentBlock;
    
  } catch (e) {
    console.error("Error checking deposits:", e);
  }
  
  return deposits;
};

/**
 * Process detected deposits - record to Lisk ledger and save to Firestore
 */
export const processDeposits = async (deposits: DepositEvent[]): Promise<void> => {
  for (const deposit of deposits) {
    try {
      // Check if already processed
      const alreadyProcessed = await isTxProcessed(deposit.chainId, deposit.txHash);
      
      if (alreadyProcessed) {
        console.log(`Tx ${deposit.txHash} already processed, skipping`);
        continue;
      }
      
      // Record to Lisk ledger contract
      const liskTxHash = await recordDeposit(
        deposit.userAddress,
        deposit.chainId,
        deposit.tokenAddress,
        deposit.amount,
        deposit.txHash
      );
      
      // Save to Firestore for history
      await db.collection("deposits").add({
        userAddress: deposit.userAddress,
        sourceChainId: deposit.chainId,
        tokenAddress: deposit.tokenAddress,
        amount: deposit.amount,
        amountFormatted: ethers.formatEther(deposit.amount),
        sourceTxHash: deposit.txHash,
        liskTxHash: liskTxHash,
        blockNumber: deposit.blockNumber,
        timestamp: new Date(deposit.timestamp * 1000).toISOString(),
        processedAt: new Date().toISOString(),
        status: "recorded",
      });
      
      console.log(`Deposit recorded: ${ethers.formatEther(deposit.amount)} POL from ${deposit.userAddress}`);
      
    } catch (e) {
      console.error(`Error processing deposit ${deposit.txHash}:`, e);
      
      // Save failed deposit for retry
      await db.collection("failed_deposits").add({
        ...deposit,
        error: e instanceof Error ? e.message : "Unknown error",
        timestamp: new Date().toISOString(),
      });
    }
  }
};

/**
 * Main listener function - call this periodically
 */
export const runDepositListener = async (): Promise<{
  depositsFound: number;
  depositsProcessed: number;
}> => {
  console.log("Running deposit listener...");
  
  const deposits = await checkNewDeposits();
  
  if (deposits.length > 0) {
    console.log(`Found ${deposits.length} new deposits`);
    await processDeposits(deposits);
  }
  
  return {
    depositsFound: deposits.length,
    depositsProcessed: deposits.length,
  };
};

/**
 * Manual deposit recording (for testing or manual top-up)
 */
export const manualRecordDeposit = async (
  userAddress: string,
  chainId: number,
  tokenAddress: string,
  amount: string,
  txHash: string
): Promise<string> => {
  // Validate tx exists on source chain
  let provider;
  if (chainId === 137 || chainId === 80001 || chainId === 80002) {
    provider = polygonProvider;
  } else {
    throw new Error(`Unsupported chain: ${chainId}`);
  }
  
  const tx = await provider.getTransaction(txHash);
  if (!tx) {
    throw new Error(`Transaction not found: ${txHash}`);
  }
  
  // Verify recipient matches
  if (tx.to?.toLowerCase() !== userAddress.toLowerCase()) {
    throw new Error(`Transaction recipient does not match user address`);
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
};
