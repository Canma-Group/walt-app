import { ethers } from 'ethers';
import * as fs from 'fs';
import * as path from 'path';
import dotenv from 'dotenv';

dotenv.config();

async function main() {
  console.log('🚀 Deploying WaltQRPayV3 (Multi-Token Support)...\n');

  // Load environment
  const rpcUrl = process.env.LISK_RPC_URL || 'https://rpc.sepolia-api.lisk.com';
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  
  if (!privateKey) {
    throw new Error('DEPLOYER_PRIVATE_KEY not set');
  }

  // Token addresses
  const LSK_TOKEN = process.env.MOCK_LSK_ADDRESS || '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
  const ETH_TOKEN = process.env.MOCK_ETH_ADDRESS || '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3';
  const POL_TOKEN = process.env.MOCK_POL_ADDRESS || '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e';

  // Connect to network
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log(`📡 Network: Lisk Sepolia`);
  console.log(`👛 Deployer: ${wallet.address}`);
  
  const balance = await provider.getBalance(wallet.address);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);

  // Load compiled contract
  const contractPath = path.join(__dirname, '../artifacts/contracts/WaltQRPayV3.sol/WaltQRPayV3.json');
  
  if (!fs.existsSync(contractPath)) {
    console.log('⚠️ Contract not compiled. Please run: npx hardhat compile');
    process.exit(1);
  }

  const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
  const bytecode = contractJson.bytecode;
  const abi = contractJson.abi;

  // Deploy parameters
  const admin = wallet.address;
  const feeCollector = process.env.ADMIN_WALLET_ADDRESS || wallet.address;
  const platformFeeBps = 200; // 2%
  const paymentTimeout = 7 * 24 * 60 * 60; // 7 days

  console.log('📋 Deployment Parameters:');
  console.log(`   Admin: ${admin}`);
  console.log(`   Fee Collector: ${feeCollector}`);
  console.log(`   Platform Fee: ${platformFeeBps / 100}%`);
  console.log(`   Payment Timeout: ${paymentTimeout / 86400} days\n`);

  // Deploy contract
  console.log('📦 Deploying contract...');
  
  const factory = new ethers.ContractFactory(abi, bytecode, wallet);
  const contract = await factory.deploy(
    admin,
    feeCollector,
    platformFeeBps,
    paymentTimeout
  );

  console.log(`⏳ Waiting for deployment...`);
  await contract.waitForDeployment();

  const contractAddress = await contract.getAddress();
  console.log(`✅ WaltQRPayV3 deployed at: ${contractAddress}\n`);

  // Whitelist tokens
  console.log('🪙 Whitelisting tokens...');
  
  const waltQRPay = new ethers.Contract(contractAddress, abi, wallet);

  // Add LSK
  console.log(`   Whitelisting LSK: ${LSK_TOKEN}`);
  let tx = await waltQRPay.setTokenWhitelist(LSK_TOKEN, true);
  await tx.wait();

  // Add ETH
  console.log(`   Whitelisting ETH: ${ETH_TOKEN}`);
  tx = await waltQRPay.setTokenWhitelist(ETH_TOKEN, true);
  await tx.wait();

  // Add POL
  console.log(`   Whitelisting POL: ${POL_TOKEN}`);
  tx = await waltQRPay.setTokenWhitelist(POL_TOKEN, true);
  await tx.wait();

  console.log('✅ Tokens whitelisted successfully!\n');

  // Verify tokens
  console.log('🔍 Verifying token whitelist...');
  const lskSupported = await waltQRPay.isTokenWhitelisted(LSK_TOKEN);
  const ethSupported = await waltQRPay.isTokenWhitelisted(ETH_TOKEN);
  const polSupported = await waltQRPay.isTokenWhitelisted(POL_TOKEN);
  
  console.log(`   LSK whitelisted: ${lskSupported}`);
  console.log(`   ETH whitelisted: ${ethSupported}`);
  console.log(`   POL whitelisted: ${polSupported}\n`);

  // Get version
  const version = await waltQRPay.getVersion();
  console.log(`📌 Contract Version: ${version}\n`);

  // Save deployment info
  const deploymentInfo = {
    contractAddress,
    network: 'lisk-sepolia',
    chainId: 4202,
    deployer: wallet.address,
    deployedAt: new Date().toISOString(),
    version,
    tokens: {
      LSK: LSK_TOKEN,
      ETH: ETH_TOKEN,
      POL: POL_TOKEN,
    },
    parameters: {
      admin,
      feeCollector,
      platformFeeBps,
      paymentTimeout,
    },
  };

  const deploymentPath = path.join(__dirname, '../deployments/waltqrpay-v3.json');
  fs.mkdirSync(path.dirname(deploymentPath), { recursive: true });
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  
  console.log(`💾 Deployment info saved to: ${deploymentPath}`);
  console.log('\n🎉 Deployment complete!');
  console.log(`\n📝 Add to .env:`);
  console.log(`WALTQRPAY_V3_ADDRESS=${contractAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Deployment failed:', error);
    process.exit(1);
  });
