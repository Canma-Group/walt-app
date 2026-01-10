import {ethers} from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

// Lisk Sepolia Configuration
export const LISK_CONFIG = {
  rpcUrl: process.env.LISK_RPC_URL || "https://rpc.sepolia-api.lisk.com",
  chainId: parseInt(process.env.LISK_CHAIN_ID || "4202"),
  blockExplorer: "https://sepolia-blockscout.lisk.com",
  name: "Lisk Sepolia Testnet",
  currency: {
    name: "Lisk",
    symbol: "LSK",
    decimals: 18,
  },
};

// Initialize Provider
export const liskProvider = new ethers.JsonRpcProvider(LISK_CONFIG.rpcUrl);

// Hot Wallet (Backend wallet for automated transfers)
let hotWalletInstance: ethers.Wallet | null = null;

export const getHotWallet = (): ethers.Wallet => {
  if (!hotWalletInstance) {
    const privateKey = process.env.HOT_WALLET_PRIVATE_KEY;
    
    if (!privateKey || privateKey === "0x...") {
      throw new Error(
        "HOT_WALLET_PRIVATE_KEY not configured. Please set it in .env file"
      );
    }

    hotWalletInstance = new ethers.Wallet(privateKey, liskProvider);
    console.log("Hot Wallet initialized:", hotWalletInstance.address);
  }

  return hotWalletInstance;
};

// Helper: Get LSK balance for any address
export const getLSKBalance = async (address: string): Promise<string> => {
  const balance = await liskProvider.getBalance(address);
  return ethers.formatEther(balance);
};

// Helper: Send LSK from hot wallet to user
export const sendLSK = async (
  toAddress: string,
  amountInLSK: string
): Promise<string> => {
  const hotWallet = getHotWallet();
  
  const tx = await hotWallet.sendTransaction({
    to: toAddress,
    value: ethers.parseEther(amountInLSK),
  });

  await tx.wait();
  return tx.hash;
};


