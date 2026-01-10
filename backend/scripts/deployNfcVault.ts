import { ethers } from 'ethers';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

dotenv.config();

// Lisk Sepolia config
const LISK_SEPOLIA_RPC = 'https://rpc.sepolia-api.lisk.com';
const CHAIN_ID = 4202;

// NfcVoucherVault bytecode (compiled from Solidity)
// We'll compile it inline using solc
const solc = require('solc');

async function main() {
  console.log('=== Deploying NfcVoucherVault to Lisk Sepolia ===\n');

  // Get private key from env
  const privateKey = process.env.HOT_WALLET_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error('HOT_WALLET_PRIVATE_KEY not set in .env');
  }

  // Setup provider and wallet
  const provider = new ethers.JsonRpcProvider(LISK_SEPOLIA_RPC);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log('Deployer address:', wallet.address);

  // Check balance
  const balance = await provider.getBalance(wallet.address);
  console.log('Balance:', ethers.formatEther(balance), 'LSK\n');

  if (balance < ethers.parseEther('0.01')) {
    throw new Error('Insufficient balance for deployment. Need at least 0.01 LSK');
  }

  // Read contract source
  const contractPath = path.join(__dirname, '../contracts/NfcVoucherVault.sol');
  const contractSource = fs.readFileSync(contractPath, 'utf8');

  // Read OpenZeppelin dependencies
  const ozBasePath = path.join(__dirname, '../node_modules/@openzeppelin/contracts');
  
  function findImports(importPath: string) {
    try {
      let fullPath: string;
      if (importPath.startsWith('@openzeppelin/contracts/')) {
        fullPath = path.join(ozBasePath, importPath.replace('@openzeppelin/contracts/', ''));
      } else {
        fullPath = path.join(__dirname, '../contracts', importPath);
      }
      const content = fs.readFileSync(fullPath, 'utf8');
      return { contents: content };
    } catch (e) {
      return { error: `File not found: ${importPath}` };
    }
  }

  console.log('Compiling contract...');

  // Compile contract
  const input = {
    language: 'Solidity',
    sources: {
      'NfcVoucherVault.sol': {
        content: contractSource,
      },
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      outputSelection: {
        '*': {
          '*': ['abi', 'evm.bytecode'],
        },
      },
    },
  };

  const output = JSON.parse(
    solc.compile(JSON.stringify(input), { import: findImports })
  );

  // Check for errors
  if (output.errors) {
    const errors = output.errors.filter((e: any) => e.severity === 'error');
    if (errors.length > 0) {
      console.error('Compilation errors:');
      errors.forEach((e: any) => console.error(e.formattedMessage));
      throw new Error('Compilation failed');
    }
    // Show warnings
    output.errors
      .filter((e: any) => e.severity === 'warning')
      .forEach((e: any) => console.warn('Warning:', e.message));
  }

  const contract = output.contracts['NfcVoucherVault.sol']['NfcVoucherVault'];
  const abi = contract.abi;
  const bytecode = contract.evm.bytecode.object;

  console.log('Compilation successful!\n');

  // Deploy contract
  console.log('Deploying contract...');

  const factory = new ethers.ContractFactory(abi, bytecode, wallet);
  
  // Estimate gas
  const deployTx = await factory.getDeployTransaction();
  const estimatedGas = await provider.estimateGas({
    ...deployTx,
    from: wallet.address,
  });
  
  console.log('Estimated gas:', estimatedGas.toString());

  // Deploy with gas buffer
  const deployedContract = await factory.deploy({
    gasLimit: (estimatedGas * BigInt(120)) / BigInt(100),
  });

  console.log('Transaction hash:', deployedContract.deploymentTransaction()?.hash);
  console.log('Waiting for confirmation...\n');

  await deployedContract.waitForDeployment();

  const contractAddress = await deployedContract.getAddress();

  console.log('=== DEPLOYMENT SUCCESSFUL ===');
  console.log('Contract address:', contractAddress);
  console.log('Chain: Lisk Sepolia (4202)');
  console.log('Block explorer: https://sepolia-blockscout.lisk.com/address/' + contractAddress);
  console.log('\n=== NEXT STEPS ===');
  console.log('1. Update NFC_VAULT_ADDRESSES in nfcVoucherService.ts:');
  console.log(`   'lisk-sepolia': '${contractAddress}'`);
  console.log('2. Update _chainConfigs in nfc_payment_page.dart:');
  console.log(`   'vaultAddress': '${contractAddress}'`);

  // Save deployment info
  const deploymentInfo = {
    contractAddress,
    chainId: CHAIN_ID,
    chainName: 'Lisk Sepolia',
    deployedAt: new Date().toISOString(),
    deployer: wallet.address,
    txHash: deployedContract.deploymentTransaction()?.hash,
  };

  const deploymentPath = path.join(__dirname, '../deployments/nfc-vault-lisk-sepolia.json');
  fs.mkdirSync(path.dirname(deploymentPath), { recursive: true });
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log('\nDeployment info saved to:', deploymentPath);

  // Save ABI
  const abiPath = path.join(__dirname, '../deployments/NfcVoucherVault.abi.json');
  fs.writeFileSync(abiPath, JSON.stringify(abi, null, 2));
  console.log('ABI saved to:', abiPath);

  return contractAddress;
}

main()
  .then((address) => {
    console.log('\nDone! Contract deployed at:', address);
    process.exit(0);
  })
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
