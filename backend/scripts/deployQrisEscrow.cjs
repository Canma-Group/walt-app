const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // LSK Token address on Lisk Mainnet
  const LSK_TOKEN_ADDRESS = "0xac485391EB2d7D88253a7F1eF18C37f4571c1571";
  
  // Admin wallet (fee collector) - receives 2% platform fee
  const ADMIN_WALLET = process.env.ADMIN_WALLET_ADDRESS || "0x8de2dc121229FfA255742Dd65000e34231f6031D";
  
  console.log("=".repeat(60));
  console.log("Deploying QrisEscrow to Lisk Mainnet...");
  console.log("=".repeat(60));
  console.log(`\nLSK Token: ${LSK_TOKEN_ADDRESS}`);
  console.log(`Admin Wallet (Fee Collector): ${ADMIN_WALLET}`);
  console.log(`Platform Fee: 2%\n`);

  const QrisEscrow = await hre.ethers.getContractFactory("QrisEscrow");
  const escrow = await QrisEscrow.deploy(LSK_TOKEN_ADDRESS, ADMIN_WALLET);

  await escrow.waitForDeployment();

  const address = await escrow.getAddress();
  
  console.log("=".repeat(60));
  console.log(`✅ QrisEscrow deployed to: ${address}`);
  console.log("=".repeat(60));
  console.log(`\n📋 Update your .env file:`);
  console.log(`   ESCROW_CONTRACT_ADDRESS=${address}`);
  console.log(`\n📋 Update Flutter app:`);
  console.log(`   lib/config/env.dart -> escrowContractAddress = '${address}'`);
  console.log(`\n🔗 View on Blockscout:`);
  console.log(`   https://blockscout.lisk.com/address/${address}`);
  console.log(`\n💰 Fee Flow:`);
  console.log(`   User pays LSK → 2% goes to ${ADMIN_WALLET}`);
  console.log(`                 → 98% locked in escrow for merchant`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
