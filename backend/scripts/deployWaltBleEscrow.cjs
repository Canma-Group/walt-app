const hre = require("hardhat");

async function main() {
  console.log("╔═══════════════════════════════════════════════════════════════╗");
  console.log("║          DEPLOYING WALT BLE ESCROW CONTRACT                   ║");
  console.log("║          Offline P2P Payments via Bluetooth                   ║");
  console.log("╚═══════════════════════════════════════════════════════════════╝");
  console.log("");

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "ETH");
  console.log("");

  // Fee collector = hot wallet
  const feeCollector = "0x8de2dc121229FfA255742Dd65000e34231f6031D";
  console.log("Fee Collector:", feeCollector);
  console.log("");

  console.log("Deploying WaltBleEscrow...");
  const WaltBleEscrow = await hre.ethers.getContractFactory("WaltBleEscrow");
  const contract = await WaltBleEscrow.deploy(feeCollector);
  
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  
  console.log("");
  console.log("╔═══════════════════════════════════════════════════════════════╗");
  console.log("║                    DEPLOYMENT SUCCESSFUL                      ║");
  console.log("╠═══════════════════════════════════════════════════════════════╣");
  console.log("║  Contract: WaltBleEscrow                                      ║");
  console.log(`║  Address:  ${address}  ║`);
  console.log("╠═══════════════════════════════════════════════════════════════╣");
  console.log("║  Fee Structure:                                               ║");
  console.log("║  • Percentage: 0.5% (50 basis points)                         ║");
  console.log("║  • Minimum: 0.1 LSK                                           ║");
  console.log("║  • Formula: max(0.1 LSK, 0.5% of amount)                      ║");
  console.log("╠═══════════════════════════════════════════════════════════════╣");
  console.log("║  Fee Examples:                                                ║");
  console.log("║  •  10 LSK → Fee: 0.1 LSK (min)  → Receiver: 9.9 LSK          ║");
  console.log("║  •  50 LSK → Fee: 0.25 LSK      → Receiver: 49.75 LSK         ║");
  console.log("║  • 100 LSK → Fee: 0.5 LSK       → Receiver: 99.5 LSK          ║");
  console.log("║  • 500 LSK → Fee: 2.5 LSK       → Receiver: 497.5 LSK         ║");
  console.log("╚═══════════════════════════════════════════════════════════════╝");
  console.log("");
  console.log("Verify command:");
  console.log(`npx hardhat verify --network liskSepolia ${address} ${feeCollector}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
