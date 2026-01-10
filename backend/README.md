# 📁 Backend Structure - bangkingt_app_backend/

Backend untuk Canma Wallet menggunakan Firebase Cloud Functions + Lisk blockchain.

## 📦 Struktur Folder

```
bangkingt_app_backend/
├── src/
│   ├── index.ts              # Main entry point, exports all functions
│   │
│   ├── config/               # Configuration files
│   │   ├── firebase.ts       # Firebase Admin SDK initialization
│   │   ├── lisk.ts           # Lisk blockchain provider & hot wallet
│   │   └── xendit.ts         # Xendit client initialization
│   │
│   ├── services/             # Business logic services
│   │   ├── walletService.ts  # Transfer LSK, calculate rates
│   │   └── onrampService.ts  # Create QRIS payments via Xendit
│   │
│   ├── callable/             # HTTPS Callable Functions (called from Flutter)
│   │   ├── createQRIS.ts     # Create QRIS for top-up
│   │   └── getUserBalance.ts # Get user's LSK balance
│   │
│   └── webhooks/             # HTTP endpoints for external webhooks
│       └── xendit.ts         # Xendit payment webhook handler
│
├── package.json              # Node.js dependencies
├── tsconfig.json             # TypeScript configuration
├── .eslintrc.js              # ESLint rules
├── .gitignore                # Git ignore patterns
└── .env.example              # Environment variables template
```

## 🚀 Setup

### 1. Install Dependencies
```bash
cd bangkingt_app_backend
npm install
```

### 2. Configure Environment
```bash
# Copy template
cp .env.example .env

# Edit .env and add:
# - HOT_WALLET_PRIVATE_KEY
# - XENDIT_API_KEY
# - XENDIT_CALLBACK_TOKEN
```

### 3. Build TypeScript
```bash
npm run build
```

### 4. Test Locally
```bash
npm run serve
# Opens Firebase Emulator at http://localhost:4000
```

### 5. Deploy to Firebase
```bash
npm run deploy
```

## 📝 Available Functions

### Callable Functions (from Flutter)
- **createQRIS** - Create QRIS payment for top-up
- **getBalance** - Get user's LSK balance from blockchain

### HTTP Endpoints (webhooks)
- **webhooks/xendit-webhook** - Receives Xendit payment notifications

## 🔑 Environment Variables

Create `.env` file with these variables:

```bash
# Lisk Blockchain
LISK_RPC_URL=https://rpc.sepolia-api.lisk.com
LISK_CHAIN_ID=4202
HOT_WALLET_PRIVATE_KEY=0x... # Backend wallet private key

# Xendit (Indonesia payment gateway)
XENDIT_API_KEY=xnd_development_...
XENDIT_CALLBACK_TOKEN=random_secret_string

# Firebase
FIREBASE_PROJECT_ID=canma-wallet

# Exchange Rate
LSK_TO_IDR_RATE=5000 # 1 LSK = 5000 IDR
```

## 🧪 Testing

### Test Functions Locally
```bash
# Start emulator
npm run serve

# In another terminal, test with curl:
curl -X POST http://localhost:5001/canma-wallet/us-central1/webhooks \
  -H "Content-Type: application/json" \
  -H "x-callback-token: your_token" \
  -d '{"external_id":"test","status":"COMPLETED","amount":50000}'
```

### Test from Flutter
Make sure to set emulator mode in Flutter:
```dart
// lib/services/cloud_functions_service.dart
_functions.useFunctionsEmulator('localhost', 5001);
```

## 📊 Function Flow

### Top-Up Flow
```
1. User clicks "Top-Up" in Flutter app
2. Flutter calls createQRIS(amount, walletAddress)
3. Backend creates QRIS via Xendit API
4. Xendit returns QRIS image URL
5. User scans QR with GoPay/OVO
6. Xendit sends webhook to /webhooks/xendit-webhook
7. Backend verifies webhook
8. Backend calculates LSK amount from IDR
9. Backend hot wallet transfers LSK to user
10. Transaction logged in Firestore
11. User sees balance updated in app
```

## 🔒 Security

- ✅ Webhook signature verification
- ✅ Firebase Auth context in Callable functions
- ✅ Environment variables for secrets
- ✅ Input validation on all endpoints
- ✅ Firestore security rules

## 📚 Key Files Explained

| File | Purpose |
|------|---------|
| `index.ts` | Exports all cloud functions |
| `config/lisk.ts` | Hot wallet management, LSK transfers |
| `config/xendit.ts` | QRIS payment initialization |
| `callable/createQRIS.ts` | Flutter → Create QRIS payment |
| `callable/getUserBalance.ts` | Flutter → Check balance |
| `webhooks/xendit.ts` | Xendit → Process payment |
| `services/walletService.ts` | Transfer LSK logic |
| `services/onrampService.ts` | QRIS creation logic |

## 🐛 Troubleshooting

### "HOT_WALLET_PRIVATE_KEY not configured"
- Create `.env` file
- Add private key from generated wallet
- Fund wallet at https://sepolia-faucet.lisk.com

### "Xendit API error"
- Verify API key is valid (xnd_development_...)
- Check QRIS is enabled in Xendit dashboard

### "Build errors"
- Run `npm install` to get dependencies
- Check TypeScript version: `npm list typescript`

## 📞 Commands Reference

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Watch mode (auto-rebuild)
npm run build:watch

# Local testing
npm run serve

# Deploy to Firebase
npm run deploy

# View logs
npm run logs

# Run Firebase shell
npm run shell
```

---

Built for **Canma Wallet** - Lisk Crypto Banking MVP


