import {ethers} from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

// Polygon Configuration (Mainnet for real POL)
export const POLYGON_CONFIG = {
  rpcUrl: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com",
  chainId: parseInt(process.env.POLYGON_CHAIN_ID || "137"),
  blockExplorer: "https://polygonscan.com",
  name: "Polygon Mainnet",
  currency: {
    name: "POL",
    symbol: "POL",
    decimals: 18,
  },
};

// Initialize Polygon Provider
export const polygonProvider = new ethers.JsonRpcProvider(POLYGON_CONFIG.rpcUrl);

// Helper: Get POL balance for any address
export const getPOLBalance = async (address: string): Promise<string> => {
  const balance = await polygonProvider.getBalance(address);
  return ethers.formatEther(balance);
};

// Helper: Get ERC20 token balance
export const getERC20Balance = async (
  tokenAddress: string,
  walletAddress: string
): Promise<string> => {
  const erc20Abi = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)",
  ];
  
  const contract = new ethers.Contract(tokenAddress, erc20Abi, polygonProvider);
  const balance = await contract.balanceOf(walletAddress);
  const decimals = await contract.decimals();
  
  return ethers.formatUnits(balance, decimals);
};

// Popular tokens on Polygon (for reference)
export const POLYGON_TOKENS = {
  // Native
  POL: "0x0000000000000000000000000000000000000000", // Native POL (address(0))
  
  // Stablecoins
  USDC: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", // USDC native
  USDT: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", // USDT
  DAI: "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",  // DAI
  
  // Popular meme coins
  SHIB: "0x6f8a06447Ff6FcF75d803135a7de15CE88C1d4ec", // SHIB
  PEPE: "0xA9E8ACF069C58aEc8825542845Fd754e41a9489A", // PEPE (bridged)
  
  // Wrapped tokens
  WETH: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", // Wrapped ETH
  WBTC: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", // Wrapped BTC
};
