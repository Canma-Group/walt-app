/**
 * Deploy SplitBillWithFee contract to Lisk Sepolia
 * Run: npx hardhat run scripts/deploySplitBillWithFee.cjs --network liskSepolia
 */

const hre = require("hardhat");

async function main() {
  console.log("=== Deploying SplitBillWithFee to Lisk Sepolia ===\n");

  const LSK_TOKEN = "0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e";
  const HOT_WALLET = "0x8de2dc121229FfA255742Dd65000e34231f6031D"; // Fee collector

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "ETH\n");

  console.log("Deploying SplitBillWithFee...");
  console.log("  Payment Token:", LSK_TOKEN);
  console.log("  Fee Collector:", HOT_WALLET);
  console.log("  Fee Scheme: Max(0.1 LSK, 1% of total)\n");

  const SplitBillWithFee = await hre.ethers.getContractFactory("SplitBillWithFee");
  const contract = await SplitBillWithFee.deploy(LSK_TOKEN, HOT_WALLET);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("\n✅ SplitBillWithFee deployed to:", address);

  // Test fee calculation
  const fee1 = await contract.estimateFee(hre.ethers.parseEther("5")); // 5 LSK
  const fee2 = await contract.estimateFee(hre.ethers.parseEther("50")); // 50 LSK
  const fee3 = await contract.estimateFee(hre.ethers.parseEther("100")); // 100 LSK

  console.log("\n=== Fee Examples ===");
  console.log("  5 LSK bill  → Fee:", hre.ethers.formatEther(fee1), "LSK (min 0.1)");
  console.log("  50 LSK bill → Fee:", hre.ethers.formatEther(fee2), "LSK (0.5 = 1%)");
  console.log("  100 LSK bill → Fee:", hre.ethers.formatEther(fee3), "LSK (1 = 1%)");

  console.log("\n=== Update env.dart ===");
  console.log(`  static const String splitBillEscrowAddress = '${address}';`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
