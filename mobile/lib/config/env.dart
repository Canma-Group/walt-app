/// Environment Configuration for Canma Wallet
/// LISK SEPOLIA TESTNET - For hackathon demo only
class Env {
  // Web3Auth Configuration
  static const String web3AuthClientId = 'BEMTjA3IWuDj3LQPDPW_VY8E_7UXtXXsl1_vrIyYh9SFG-7BQ9oilXQGzhr9NOTHKg6PypsCUDfYYmyHq7TPo2A';
  static const String web3AuthProjectName = 'dapp_canma';
  static const String web3AuthClientSecret = '9e0fe7e06a5263f4d621f8d7a78850e93c9a190b62f525e4787914e6bdb48a72'; // For backend use only
  static const String web3AuthJwksEndpoint = 'https://api-auth.web3auth.io/.well-known/jwks.json';
  static const String web3AuthNetwork = 'sapphire_devnet'; // sesuai dengan dashboard
  static const String web3AuthVerifierName = 'dapp_canma'; // Must match Web3Auth dashboard verifier name
  
  // Lisk Sepolia Testnet Configuration
  static const String liskRpcUrl = 'https://rpc.sepolia-api.lisk.com';
  static const int liskChainId = 4202; // Lisk Sepolia
  static const String liskChainName = 'Lisk Sepolia Testnet';
  static const String liskBlockExplorer = 'https://sepolia-blockscout.lisk.com';
  static const String liskCurrencySymbol = 'LSK';
  static const int liskCurrencyDecimals = 18;
  
  // Mock Token Contracts (ERC-20 for testnet simulation)
  // Note: These are test tokens for hackathon demo
  static const String lskTokenAddress = '0x4270A0c8676A10ab8CbE3e92bFd187D94C8f248e';
  static const String ethTokenAddress = '0x292D54495d4C9Af56D86fA6cAF25591037EF80b3';
  static const String polTokenAddress = '0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e';
  
  // Token address map for dynamic lookup
  static String getTokenAddress(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'LSK': return lskTokenAddress;
      case 'ETH': return ethTokenAddress;
      case 'POL': return polTokenAddress;
      default: return lskTokenAddress;
    }
  }
  
  // QrisEscrow Contract (handles QRIS payments with 1% fee split)
  // V1: 0x11EEbc7f31EF98967eDB824e05DA21Ec6F133dc2
  // V2: Multi-role, Pausable, Multi-token support
  static const String escrowContractAddress = '0xda7c9CF0988547d6F88899A3a822630bAD52060d';
  
  // Admin/Fee Collector Wallet
  static const String adminWalletAddress = '0x91A1Dc9CEf03BB67DfB181eed683d5Dd94244AAC';
  
  // Firebase Configuration
  static const String firebaseProjectId = 'canma-wallet';
  
  // Feature Flags
  static const bool enableDebugLogs = true;
  static const bool enableTestnet = true;
  
  // Backend API URL (use your computer's IP for mobile testing)
  static const String backendUrl = 'http://203.194.112.143:3000';
  
  // Cross-Chain Ledger Contract (deploy via Remix, then paste address here)
  static const String ledgerContractAddress = ''; // Set after deployment
  
  // WaltSplitBillV3 Contract for Split Bill feature
  // Deployed on Lisk Sepolia - handles escrow for split payments
  // Verified: https://sepolia-blockscout.lisk.com/address/0x49c19A8fD9f35f858DFfF6F2c0DE77a062d71B7c#code
  static const String splitBillContractAddress = '0x49c19A8fD9f35f858DFfF6F2c0DE77a062d71B7c';
}


