/**
 * Deploy SimpleSplitBill contract to Lisk Sepolia
 * Run: npx hardhat run scripts/deploySimpleSplitBill.cjs --network liskSepolia
 */

const hre = require("hardhat");

async function main() {
  console.log("=== Deploying SimpleSplitBill to Lisk Sepolia ===\n");

  // LSK Token address on Lisk Sepolia
  const LSK_TOKEN = "0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e";

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "ETH\n");

  // Deploy
  console.log("Deploying SimpleSplitBill...");
  const SimpleSplitBill = await hre.ethers.getContractFactory("SimpleSplitBill");
  const contract = await SimpleSplitBill.deploy(LSK_TOKEN);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("\n✅ SimpleSplitBill deployed to:", address);
  console.log("\nUpdate your env.dart with:");
  console.log(`  static const String simpleSplitBillAddress = '${address}';`);

  // Verify contract info
  console.log("\nContract Info:");
  console.log("  Payment Token:", await contract.paymentToken());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
