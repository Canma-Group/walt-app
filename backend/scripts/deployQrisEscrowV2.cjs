const hre = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYING QrisEscrowV2 to Lisk Sepolia Testnet");
  console.log("=".repeat(60));

  const [deployer] = await hre.ethers.getSigners();
  console.log(`\nDeployer: ${deployer.address}`);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log(`Balance: ${hre.ethers.formatEther(balance)} ETH`);

  // MockLSK token address on Lisk Sepolia
  const mockLskAddress = process.env.LSK_TOKEN_ADDRESS || "0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e";
  
  // Fee collector (admin wallet)
  const feeCollector = process.env.ADMIN_WALLET || deployer.address;

  console.log(`\nParameters:`);
  console.log(`  Default Token (MockLSK): ${mockLskAddress}`);
  console.log(`  Fee Collector: ${feeCollector}`);

  // Deploy QrisEscrowV2
  console.log(`\n📦 Deploying QrisEscrowV2...`);
  
  const QrisEscrowV2 = await hre.ethers.getContractFactory("QrisEscrowV2");
  const escrow = await QrisEscrowV2.deploy(mockLskAddress, feeCollector);
  
  await escrow.waitForDeployment();
  const escrowAddress = await escrow.getAddress();
  
  console.log(`   ✅ QrisEscrowV2 deployed at: ${escrowAddress}`);

  // Verify deployment
  console.log(`\n🔍 Verifying deployment...`);
  
  const version = await escrow.getVersion();
  console.log(`   Version: ${version}`);
  
  const defaultToken = await escrow.defaultToken();
  console.log(`   Default Token: ${defaultToken}`);
  
  const platformFeeBps = await escrow.platformFeeBps();
  console.log(`   Platform Fee: ${platformFeeBps} bps (${Number(platformFeeBps) / 100}%)`);
  
  const paymentTimeout = await escrow.paymentTimeout();
  console.log(`   Payment Timeout: ${Number(paymentTimeout) / 60} minutes`);

  // Check roles
  const ADMIN_ROLE = await escrow.ADMIN_ROLE();
  const OPERATOR_ROLE = await escrow.OPERATOR_ROLE();
  const VERIFIER_ROLE = await escrow.VERIFIER_ROLE();
  
  const hasAdmin = await escrow.hasRole(ADMIN_ROLE, deployer.address);
  const hasOperator = await escrow.hasRole(OPERATOR_ROLE, deployer.address);
  const hasVerifier = await escrow.hasRole(VERIFIER_ROLE, deployer.address);
  
  console.log(`\n👤 Deployer Roles:`);
  console.log(`   ADMIN_ROLE: ${hasAdmin}`);
  console.log(`   OPERATOR_ROLE: ${hasOperator}`);
  console.log(`   VERIFIER_ROLE: ${hasVerifier}`);

  console.log("\n" + "=".repeat(60));
  console.log("✅ DEPLOYMENT SUCCESSFUL!");
  console.log("=".repeat(60));
  console.log(`\nQrisEscrowV2: ${escrowAddress}`);
  console.log(`\nAdd to .env:`);
  console.log(`QRIS_ESCROW_V2_ADDRESS=${escrowAddress}`);
  console.log("=".repeat(60) + "\n");

  // Verify on Blockscout (optional)
  if (process.env.VERIFY_ON_DEPLOY === "true") {
    console.log("\n🔗 Verifying contract on Blockscout...");
    try {
      await hre.run("verify:verify", {
        address: escrowAddress,
        constructorArguments: [mockLskAddress, feeCollector],
      });
      console.log("   ✅ Contract verified!");
    } catch (e) {
      console.log(`   ⚠️ Verification failed: ${e.message}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
