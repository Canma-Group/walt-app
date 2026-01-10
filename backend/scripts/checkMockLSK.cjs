const hre = require("hardhat");
require("dotenv").config();

async function main() {
  const mockLskAddress = "0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e";
  const userWallet = "0x91A1Dc9CEf03BB67DfB181eed683d5Dd94244AAC";
  const hotWallet = "0x8de2dc121229FfA255742Dd65000e34231f6031D";
  
  console.log("\n" + "=".repeat(60));
  console.log("LISK SEPOLIA - MockLSK & ETH Balance Check");
  console.log("=".repeat(60));
  
  // Get MockLSK contract
  const MockLSK = await hre.ethers.getContractAt("MockLSK", mockLskAddress);
  
  // Check MockLSK balances
  const userLskBalance = await MockLSK.balanceOf(userWallet);
  const hotLskBalance = await MockLSK.balanceOf(hotWallet);
  
  console.log(`\n📍 User Wallet: ${userWallet}`);
  console.log(`   MockLSK: ${hre.ethers.formatEther(userLskBalance)} LSK`);
  
  const userEthBalance = await hre.ethers.provider.getBalance(userWallet);
  console.log(`   ETH (gas): ${hre.ethers.formatEther(userEthBalance)} ETH`);
  
  console.log(`\n📍 Hot Wallet: ${hotWallet}`);
  console.log(`   MockLSK: ${hre.ethers.formatEther(hotLskBalance)} LSK`);
  
  const hotEthBalance = await hre.ethers.provider.getBalance(hotWallet);
  console.log(`   ETH (gas): ${hre.ethers.formatEther(hotEthBalance)} ETH`);
  
  console.log("\n" + "=".repeat(60));
  
  // Summary
  if (userLskBalance == 0n) {
    console.log("❌ User wallet has NO MockLSK!");
    console.log("   Need to mint MockLSK to user wallet");
  } else {
    console.log("✅ User has MockLSK");
  }
  
  if (userEthBalance == 0n) {
    console.log("❌ User wallet has NO ETH for gas!");
    console.log("   Need to send ETH from hot wallet");
  } else {
    console.log("✅ User has ETH for gas");
  }
  
  console.log("=".repeat(60) + "\n");
}

main().catch(console.error);
