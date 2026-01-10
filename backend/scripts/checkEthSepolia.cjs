const { ethers } = require("ethers");

async function main() {
  const wallet = "0x8de2dc121229FfA255742Dd65000e34231f6031D";
  
  // Ethereum Sepolia RPC
  const provider = new ethers.JsonRpcProvider("https://rpc.sepolia.org");
  
  console.log("\n" + "=".repeat(50));
  console.log("ETHEREUM SEPOLIA - BALANCE CHECK");
  console.log("=".repeat(50));
  
  const balance = await provider.getBalance(wallet);
  console.log(`\n📍 Wallet: ${wallet}`);
  console.log(`   ETH Balance: ${ethers.formatEther(balance)} ETH`);
  
  if (balance > 0n) {
    console.log("\n✅ Wallet has ETH on Ethereum Sepolia!");
  } else {
    console.log("\n❌ Wallet has 0 ETH on Ethereum Sepolia.");
  }
  console.log("=".repeat(50) + "\n");
}

main().catch(console.error);
