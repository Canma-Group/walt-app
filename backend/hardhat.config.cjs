require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Local Hardhat Network (for hackathon demo)
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    // Lisk Mainnet
    lisk: {
      url: "https://rpc.api.lisk.com",
      chainId: 1135,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
    },
    // Lisk Sepolia Testnet
    liskSepolia: {
      url: "https://rpc.sepolia-api.lisk.com",
      chainId: 4202,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
    },
    // Alias for lisk-sepolia
    "lisk-sepolia": {
      url: "https://rpc.sepolia-api.lisk.com",
      chainId: 4202,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      lisk: "placeholder", // Blockscout doesn't need API key
      liskSepolia: "placeholder",
    },
    customChains: [
      {
        network: "lisk",
        chainId: 1135,
        urls: {
          apiURL: "https://blockscout.lisk.com/api",
          browserURL: "https://blockscout.lisk.com",
        },
      },
      {
        network: "liskSepolia",
        chainId: 4202,
        urls: {
          apiURL: "https://sepolia-blockscout.lisk.com/api",
          browserURL: "https://sepolia-blockscout.lisk.com",
        },
      },
    ],
  },
};
