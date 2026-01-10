const hre = require("hardhat");
require("dotenv").config();

async function main() {
  const userWallet = "0x91A1Dc9CEf03BB67DfB181eed683d5Dd94244AAC";
  const amountEth = "0.01"; // Send 0.01 ETH for gas
  
  console.log("\n" + "=".repeat(50));
  console.log("SENDING ETH FOR GAS TO USER WALLET");
  console.log("=".repeat(50));
  
  const [deployer] = await hre.ethers.getSigners();
  console.log(`\nFrom (Hot Wallet): ${deployer.address}`);
  console.log(`To (User Wallet): ${userWallet}`);
  console.log(`Amount: ${amountEth} ETH`);
  
  // Check balances before
  const hotBalanceBefore = await hre.ethers.provider.getBalance(deployer.address);
  const userBalanceBefore = await hre.ethers.provider.getBalance(userWallet);
  
  console.log(`\nBefore:`);
  console.log(`  Hot Wallet ETH: ${hre.ethers.formatEther(hotBalanceBefore)}`);
  console.log(`  User Wallet ETH: ${hre.ethers.formatEther(userBalanceBefore)}`);
  
  // Send ETH
  console.log(`\n📤 Sending ${amountEth} ETH...`);
  const tx = await deployer.sendTransaction({
    to: userWallet,
    value: hre.ethers.parseEther(amountEth),
  });
  
  console.log(`   TX Hash: ${tx.hash}`);
  await tx.wait();
  console.log(`   ✅ Confirmed!`);
  
  // Check balances after
  const hotBalanceAfter = await hre.ethers.provider.getBalance(deployer.address);
  const userBalanceAfter = await hre.ethers.provider.getBalance(userWallet);
  
  console.log(`\nAfter:`);
  console.log(`  Hot Wallet ETH: ${hre.ethers.formatEther(hotBalanceAfter)}`);
  console.log(`  User Wallet ETH: ${hre.ethers.formatEther(userBalanceAfter)}`);
  
  console.log("\n" + "=".repeat(50));
  console.log("✅ User wallet now has ETH for gas!");
  console.log("=".repeat(50) + "\n");
}

main().catch(console.error);
