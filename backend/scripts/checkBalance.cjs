const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // Get deployer address from private key
  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = deployer.address;
  
  // Target wallet for tokens
  const targetWallet = process.env.TARGET_WALLET_ADDRESS;
  
  console.log("\n" + "=".repeat(50));
  console.log("LISK SEPOLIA TESTNET - BALANCE CHECK");
  console.log("=".repeat(50));
  
  // Check deployer balance
  const deployerBalance = await hre.ethers.provider.getBalance(deployerAddress);
  console.log(`\n📍 Deployer Wallet: ${deployerAddress}`);
  console.log(`   ETH Balance: ${hre.ethers.formatEther(deployerBalance)} ETH`);
  
  // Check target wallet balance
  const targetBalance = await hre.ethers.provider.getBalance(targetWallet);
  console.log(`\n📍 Target Wallet: ${targetWallet}`);
  console.log(`   ETH Balance: ${hre.ethers.formatEther(targetBalance)} ETH`);
  
  console.log("\n" + "=".repeat(50));
  if (deployerBalance > 0n) {
    console.log("✅ Deployer has ETH! Ready to deploy contracts.");
  } else {
    console.log("❌ Deployer has 0 ETH. Need to bridge from Ethereum Sepolia.");
    console.log("   Bridge URL: https://sepolia-bridge.lisk.com");
  }
  console.log("=".repeat(50) + "\n");
}

main().catch(console.error);
