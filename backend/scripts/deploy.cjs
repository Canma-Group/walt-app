const hre = require("hardhat");

async function main() {
  console.log("Deploying CrossChainLedger to Lisk Sepolia...");

  const CrossChainLedger = await hre.ethers.getContractFactory("CrossChainLedger");
  const ledger = await CrossChainLedger.deploy();

  await ledger.waitForDeployment();

  const address = await ledger.getAddress();
  console.log(`\n✅ CrossChainLedger deployed to: ${address}`);
  console.log(`\n📋 Copy this address to your Flutter app:`);
  console.log(`   lib/config/env.dart -> ledgerContractAddress = '${address}'`);
  console.log(`\n🔗 View on Blockscout:`);
  console.log(`   https://sepolia-blockscout.lisk.com/address/${address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
