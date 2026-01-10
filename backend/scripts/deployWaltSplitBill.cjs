/**
 * Deploy WaltSplitBill contract to Lisk Sepolia
 * Run: npx hardhat run scripts/deployWaltSplitBill.cjs --network liskSepolia
 */

const hre = require("hardhat");

async function main() {
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║           DEPLOYING WALTSPLITBILL TO LISK SEPOLIA            ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const LSK_TOKEN = "0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e";
  const HOT_WALLET = "0x8de2dc121229FfA255742Dd65000e34231f6031D";

  const [deployer] = await hre.ethers.getSigners();
  console.log("📋 Deployment Configuration:");
  console.log("   ├─ Deployer:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("   ├─ Balance:", hre.ethers.formatEther(balance), "ETH");
  console.log("   ├─ Payment Token:", LSK_TOKEN);
  console.log("   └─ Fee Collector:", HOT_WALLET);

  console.log("\n📝 Fee Configuration:");
  console.log("   ├─ Fee Model: Hybrid (Max of minimum or percentage)");
  console.log("   ├─ Minimum Fee: 0.1 LSK");
  console.log("   ├─ Percentage: 1%");
  console.log("   └─ Formula: Max(0.1 LSK, 1% of total)");

  console.log("\n🚀 Deploying WaltSplitBill...");
  
  const WaltSplitBill = await hre.ethers.getContractFactory("WaltSplitBill");
  const contract = await WaltSplitBill.deploy(LSK_TOKEN, HOT_WALLET);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("\n✅ WaltSplitBill deployed successfully!");
  console.log("   └─ Contract Address:", address);

  // Test fee calculations
  console.log("\n📊 Fee Examples:");
  const testAmounts = [5, 10, 20, 50, 100, 500, 1000];
  for (const amount of testAmounts) {
    const amountWei = hre.ethers.parseEther(amount.toString());
    const fee = await contract.estimateFee(amountWei);
    const feeFormatted = hre.ethers.formatEther(fee);
    const percentage = (parseFloat(feeFormatted) / amount * 100).toFixed(2);
    console.log(`   ├─ ${amount} LSK → Fee: ${feeFormatted} LSK (${percentage}%)`);
  }

  // Get contract info
  console.log("\n📋 Contract Info:");
  console.log("   ├─ Payment Token:", await contract.paymentToken());
  console.log("   ├─ Fee Collector:", await contract.feeCollector());
  console.log("   ├─ Owner:", await contract.owner());
  console.log("   └─ Deployed At:", new Date((await contract.deployedAt()) * 1000n).toISOString());

  console.log("\n════════════════════════════════════════════════════════════════");
  console.log("📝 UPDATE YOUR CONFIGURATION:");
  console.log("════════════════════════════════════════════════════════════════");
  console.log("\n1. Flutter env.dart:");
  console.log(`   static const String splitBillEscrowAddress = '${address}';`);
  console.log("\n2. Backend index.ts:");
  console.log(`   const SIMPLE_SPLIT_BILL_ADDRESS = '${address}';`);
  console.log("\n3. Verify on block explorer:");
  console.log(`   npx hardhat verify --network liskSepolia ${address} ${LSK_TOKEN} ${HOT_WALLET}`);
  console.log("════════════════════════════════════════════════════════════════\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
