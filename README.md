# Walt - Web3 Digital Wallet

<div align="center">

![Walt Logo](https://img.shields.io/badge/Walt-Web3%20Wallet-blue?style=for-the-badge&logo=ethereum)
![Lisk](https://img.shields.io/badge/Lisk-Sepolia-green?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-Mobile-02569B?style=for-the-badge&logo=flutter)
![Node.js](https://img.shields.io/badge/Node.js-Backend-339933?style=for-the-badge&logo=node.js)

**A Web3 mobile wallet integrating daily financial management and crypto assets into a single platform**

[Live Demo](https://walt.rfrfrfrf.my.id) • [Documentation](https://walt.rfrfrfrf.my.id/docs) • [Smart Contracts](#smart-contracts)

</div>

---

## Overview

Walt is an application that integrates daily financial management and crypto asset management into a single platform. Users can make payments, transfers, and monitor their crypto assets all within one app.

The app is designed to reduce the complexity of using multiple separate financial applications, allowing users to manage all their financial activities more easily, efficiently, and seamlessly.

### Key Features

| Feature | Description |
|---------|-------------|
| **QR Payments (QRIS)** | Pay at any Indonesian QRIS merchant using crypto. Users pay with LSK/ETH/POL, merchants receive IDR via Xendit settlement. |
| **Crypto Asset Swap** | Exchange crypto assets directly within the app with real-time rates and 0.2% fee. |
| **Peer-to-Peer Transfer** | Send funds to contacts with gas sponsorship via barter model. |
| **NearSync (NFC)** | Transfer funds to nearby users via NFC for quick face-to-face transactions. |
| **Split Bill** | Divide expenses among multiple people with smart contract escrow for fairness and transparency. |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WALT SYSTEM ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐         ┌──────────────┐         ┌──────────────┐        │
│   │   Flutter    │   API   │   Node.js    │   RPC   │    Lisk      │        │
│   │  Mobile App  │◄───────►│   Backend    │◄───────►│   Sepolia    │        │
│   │              │         │              │         │  Blockchain  │        │
│   └──────────────┘         └──────────────┘         └──────────────┘        │
│         │                        │                        │                 │
│         │                        │                        │                 │
│   ┌─────▼─────┐            ┌─────▼─────┐            ┌─────▼─────┐           │
│   │ Web3Auth  │            │  Xendit   │            │  Smart    │           │
│   │   Keys    │            │ Settlement│            │ Contracts │           │
│   └───────────┘            └───────────┘            └───────────┘           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Smart Contracts

All smart contracts are deployed on **Lisk Sepolia Testnet** (Chain ID: 4202) and implement OpenZeppelin security patterns.

| Contract | Address | Blockscout |
|----------|---------|------------|
| **CanmaSplitBillV5** | `0x998C402E2d5A55EC599C84B7B1C446732b29E5F3` | [View](https://sepolia-blockscout.lisk.com/address/0x998C402E2d5A55EC599C84B7B1C446732b29E5F3) |
| **WaltQRPayV3** | `0x4f11677bcF14FEEfD906Dd978a4E4Ad54b4Ce194` | [View](https://sepolia-blockscout.lisk.com/address/0x4f11677bcF14FEEfD906Dd978a4E4Ad54b4Ce194) |
| **WaltSwapV2** | `0x31169C501C316Fa6ec2e4E483ab32C09F8337149` | [View](https://sepolia-blockscout.lisk.com/address/0x31169C501C316Fa6ec2e4E483ab32C09F8337149) |
| **MockLSK** | `0x4270A0c8676a10ab8cbe3e92bfd187d94c8f248e` | [View](https://sepolia-blockscout.lisk.com/address/0x4270A0c8676a10ab8cbe3e92bfd187d94c8f248e) |
| **MockPOL** | `0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e` | [View](https://sepolia-blockscout.lisk.com/address/0xEE412e79eB7F565Ec9e7c8A1b0a7eC27b63fbc5e) |

### Contract Features

- **ReentrancyGuard** - Protection against reentrancy attacks
- **Pausable** - Emergency stop mechanism
- **AccessControl** - Role-based permissions (OPERATOR_ROLE, ADMIN_ROLE)
- **SafeERC20** - Safe token transfer handling
- **Ownable2Step** - Two-step ownership transfer for security

---

## Requirements

### Backend (Node.js)

- Node.js >= 18.x
- npm >= 9.x
- PM2 (for production)

### Mobile App (Flutter)

- Flutter SDK >= 3.19.x
- Dart >= 3.3.x
- Android Studio / Xcode
- Android SDK >= 21 (Android 5.0+)

### Environment Variables

Create `.env` file in `backend/` directory:

```env
# Server
PORT=3001
NODE_ENV=production

# Blockchain
RPC_URL=https://rpc.sepolia-api.lisk.com
CHAIN_ID=4202
PRIVATE_KEY=your_operator_private_key

# Smart Contracts
SPLITBILL_CONTRACT=0x998C402E2d5A55EC599C84B7B1C446732b29E5F3
QRPAY_CONTRACT=0x4f11677bcF14FEEfD906Dd978a4E4Ad54b4Ce194
SWAP_CONTRACT=0x31169C501C316Fa6ec2e4E483ab32C09F8337149

# Xendit (for QRIS settlement)
XENDIT_SECRET_KEY=your_xendit_secret_key

# Firebase (for auth)
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_PRIVATE_KEY=your_firebase_key
FIREBASE_CLIENT_EMAIL=your_client_email
```

---

## How to Run

### 1. Backend Setup

```bash
# Navigate to backend directory
cd backend

# Install dependencies
npm install

# Development mode
npm run dev

# Production mode with PM2
pm2 start server.js --name walt-backend
pm2 save
```

### 2. Smart Contract Deployment (Optional)

```bash
cd backend

# Compile contracts
npx hardhat compile

# Deploy to Lisk Sepolia
npx hardhat run scripts/deploy.js --network liskSepolia

# Verify on Blockscout
npx hardhat verify --network liskSepolia <CONTRACT_ADDRESS>
```

### 3. Mobile App Setup

```bash
# Navigate to mobile directory
cd mobile

# Get Flutter dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Build release APK
flutter build apk --release --split-per-abi
```

---

## System Workflow

### QRIS Payment Flow (Crypto to IDR)

```
User                    WaltApp                 Backend                 WaltQRPayV3             Xendit              Merchant
  │                        │                       │                        │                      │                    │
  │ 1. Scan QRIS           │                       │                        │                      │                    │
  │───────────────────────>│                       │                        │                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │ 2. Create Payment     │                        │                      │                    │
  │                        │──────────────────────>│                        │                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │ 3. Get LSK/IDR rate    │                      │                    │
  │                        │                       │    Calculate amount    │                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │<──────────────────────│                        │                      │                    │
  │                        │   PaymentIntent       │                        │                      │                    │
  │                        │                       │                        │                      │                    │
  │<───────────────────────│                       │                        │                      │                    │
  │  Show: "Pay 2.5 LSK"   │                       │                        │                      │                    │
  │                        │                       │                        │                      │                    │
  │ 4. Confirm             │                       │                        │                      │                    │
  │───────────────────────>│                       │                        │                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │ 5. approve() + pay()  │                        │                      │                    │
  │                        │───────────────────────────────────────────────>│                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │                        │ ESCROW LOCKED        │                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │<───────────────────────│                      │                    │
  │                        │                       │   PaymentCreated       │                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │ 6. release()           │                      │                    │
  │                        │                       │───────────────────────>│                      │                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │                        │ Transfer to          │                    │
  │                        │                       │                        │ FeeCollector         │                    │
  │                        │                       │                        │─────────────────────>│                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │ 7. Create disbursement │                      │                    │
  │                        │                       │─────────────────────────────────────────────>│                    │
  │                        │                       │                        │                      │                    │
  │                        │                       │                        │                      │ 8. Bank Transfer   │
  │                        │                       │                        │                      │───────────────────>│
  │                        │                       │                        │                      │                    │
  │<───────────────────────│                       │                        │                      │                    │
  │  Payment Success!      │                       │                        │                      │                    │
```

### Split Bill Flow

1. **Creator** creates bill with participants and deadline
2. **Participants** pay their share to smart contract escrow
3. When all paid → Creator can **withdraw** funds
4. If deadline passed → Participants can **claim refund**

### WaltSwap Flow

1. User selects **fromToken** and **toToken**
2. Backend calculates quote with real-time prices
3. User approves token spend
4. Smart contract executes swap with 0.2% fee
5. User receives swapped tokens

---

## Project Structure

```
walt-app/
├── backend/                    # Node.js Backend
│   ├── contracts/              # Solidity Smart Contracts
│   │   ├── CanmaSplitBillV5.sol
│   │   ├── WaltQRPayV3.sol
│   │   └── WaltSwapV2.sol
│   ├── scripts/                # Deployment scripts
│   ├── server.js               # Express server
│   ├── hardhat.config.js       # Hardhat configuration
│   └── package.json
│
├── mobile/                     # Flutter Mobile App
│   ├── lib/
│   │   ├── ui/                 # UI Components & Pages
│   │   │   ├── pages/
│   │   │   │   ├── home_page.dart
│   │   │   │   ├── scan_qris_page.dart
│   │   │   │   ├── split_bill_page.dart
│   │   │   │   └── swap_page.dart
│   │   │   └── widgets/
│   │   ├── services/           # Backend & Blockchain Services
│   │   │   ├── qris_payment_service.dart
│   │   │   ├── canma_splitbill_v5_service.dart
│   │   │   └── wallet_service.dart
│   │   └── main.dart
│   ├── pubspec.yaml
│   └── android/
│
└── README.md
```

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Mobile** | Flutter 3.19, Dart 3.3, web3dart, BLoC |
| **Backend** | Node.js 18, Express, ethers.js |
| **Blockchain** | Lisk Sepolia, Solidity 0.8.20, Hardhat |
| **Auth** | Web3Auth (non-custodial), Firebase Auth |
| **Payment** | Xendit xenPlatform (QRIS settlement) |
| **Security** | OpenZeppelin 5.x |

---

## Security

### Smart Contract Security
- OpenZeppelin 5.x battle-tested libraries
- ReentrancyGuard on all state-changing functions
- SafeERC20 for token transfers
- Pull-based refunds (prevents griefing)
- Role-based access control

### Application Security
- Web3Auth non-custodial key management
- Private keys stored only on user device
- PIN protection for transactions
- flutter_secure_storage (encrypted)
- HTTPS-only communication

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

---

<div align="center">

**Built for Lisk Builders Challenge 2024**

Made with ❤️ by Walt Team

</div>
