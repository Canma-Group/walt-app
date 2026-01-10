const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // Admin wallet (fee collector)
  const ADMIN_WALLET = process.env.ADMIN_WALLET_ADDRESS || "0x8de2dc121229FfA255742Dd65000e34231f6031D";
  
  console.log("=".repeat(60));
  console.log("🧪 DEPLOYING TO LISK SEPOLIA TESTNET");
  console.log("=".repeat(60));
  console.log(`\nAdmin Wallet: ${ADMIN_WALLET}`);
  console.log(`Platform Fee: 2%\n`);

  // Step 1: Deploy MockLSK Token
  console.log("📦 Step 1: Deploying MockLSK Token...");
  const MockLSK = await hre.ethers.getContractFactory("MockLSK");
  const mockLsk = await MockLSK.deploy();
  await mockLsk.waitForDeployment();
  const lskAddress = await mockLsk.getAddress();
  console.log(`   ✅ MockLSK deployed to: ${lskAddress}`);

  // Step 2: Deploy QrisEscrow with MockLSK
  console.log("\n📦 Step 2: Deploying QrisEscrow...");
  const QrisEscrow = await hre.ethers.getContractFactory("QrisEscrow");
  const escrow = await QrisEscrow.deploy(lskAddress, ADMIN_WALLET);
  await escrow.waitForDeployment();
  const escrowAddress = await escrow.getAddress();
  console.log(`   ✅ QrisEscrow deployed to: ${escrowAddress}`);

  // Step 3: Mint LSK to admin wallet for testing
  console.log("\n💰 Step 3: Minting 100,000 LSK to admin wallet...");
  const mintTx = await mockLsk.mint(ADMIN_WALLET, hre.ethers.parseEther("100000"));
  await mintTx.wait();
  console.log(`   ✅ Minted 100,000 LSK to ${ADMIN_WALLET}`);

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("🎉 DEPLOYMENT COMPLETE!");
  console.log("=".repeat(60));
  
  console.log(`
📋 CONTRACT ADDRESSES (Lisk Sepolia Testnet):
─────────────────────────────────────────────
MockLSK Token:  ${lskAddress}
QrisEscrow:     ${escrowAddress}
Admin Wallet:   ${ADMIN_WALLET}

📝 UPDATE YOUR .env FILE:
─────────────────────────────────────────────
LSK_TOKEN_ADDRESS=${lskAddress}
ESCROW_CONTRACT_ADDRESS=${escrowAddress}

📝 UPDATE FLUTTER lib/config/env.dart:
─────────────────────────────────────────────
static const String lskTokenAddress = '${lskAddress}';
static const String escrowContractAddress = '${escrowAddress}';
static const String liskRpcUrl = 'https://rpc.sepolia-api.lisk.com';
static const int liskChainId = 4202;

🔗 VIEW ON BLOCKSCOUT:
─────────────────────────────────────────────
MockLSK: https://sepolia-blockscout.lisk.com/address/${lskAddress}
Escrow:  https://sepolia-blockscout.lisk.com/address/${escrowAddress}

💰 GET FREE LSK TOKENS:
─────────────────────────────────────────────
Call mockLsk.getFreeTokens() to get 1000 LSK
Or call mockLsk.faucet(amount) for custom amount
  `);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
