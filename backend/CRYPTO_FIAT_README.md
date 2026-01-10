# Crypto-to-Fiat Payment System

## Hackathon MVP - Lisk Mainnet

A complete end-to-end prototype for processing QRIS payments using LSK cryptocurrency, with automatic conversion to IDR and simulated fiat settlement.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           BUYER FLOW                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  1. Scan QRIS Code                                                       │
│  2. Create Payment Intent (Backend generates orderId)                    │
│  3. Approve LSK Transfer to Escrow Contract                              │
│  4. Send LSK to Escrow (on Lisk Mainnet)                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      ESCROW SMART CONTRACT                               │
├─────────────────────────────────────────────────────────────────────────┤
│  • Locks LSK tokens                                                      │
│  • Emits PaymentLocked(orderId, merchantId, amount, buyer, expires)      │
│  • Admin can release() or refund()                                       │
│  • Buyer can claimExpiredRefund() after timeout                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ PaymentLocked Event
┌─────────────────────────────────────────────────────────────────────────┐
│                       BACKEND SERVICES                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐   │
│  │  Event Listener  │───▶│ Conversion Engine│───▶│   Rule Engine    │   │
│  │  (Blockchain)    │    │  (LSK → IDR)     │    │  (Auto-Approve)  │   │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘   │
│           │                       │                       │              │
│           │                       │                       ▼              │
│           │                       │              ┌──────────────────┐   │
│           │                       │              │  Settlement Bot  │   │
│           │                       │              │   (SIMULATED)    │   │
│           │                       │              └──────────────────┘   │
│           │                       │                       │              │
│           ▼                       ▼                       ▼              │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    PostgreSQL Database                           │    │
│  │  • Orders  • Trades  • Ledger  • Settlements  • Config          │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        MERCHANT (SIMULATED)                              │
├─────────────────────────────────────────────────────────────────────────┤
│  ⚠️ HACKATHON: Settlement is SIMULATED                                  │
│  • Mock bank reference generated                                         │
│  • No real fiat transfer occurs                                          │
│  • Ledger tracks gross/fees/net amounts                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📦 Components

### 1. Escrow Smart Contract (`contracts/QrisEscrow.sol`)

**Real Functionality:**
- Accepts LSK token deposits
- Locks funds in escrow
- Emits `PaymentLocked` events
- Supports refunds (admin or buyer after expiry)

**Key Functions:**
```solidity
function pay(bytes32 orderId, string merchantId, uint256 amount) external
function release(bytes32 orderId) external onlyOwner
function refund(bytes32 orderId, string reason) external onlyOwner
function claimExpiredRefund(bytes32 orderId) external
```

### 2. Event Listener (`services/escrowEventListener.ts`)

**Real Functionality:**
- Polls Lisk Mainnet for `PaymentLocked` events
- Ensures idempotency via txHash + logIndex tracking
- Creates order records in database

### 3. Conversion Engine (`services/conversionEngine.ts`)

**Real Functionality:**
- Fetches LSK/IDR price from Indodax API
- Calculates conversion amount with exchange fees

**Simulated:**
- Actual CEX trade execution (mocked)
- LSK transfer to exchange wallet (mocked)

### 4. Rule Engine (`services/ruleEngine.ts`)

**Real Functionality:**
- Amount threshold checking
- Merchant whitelist verification
- Duplicate detection
- Audit logging

**Auto-Approval Rules:**
1. `AMOUNT_THRESHOLD`: Order ≤ Rp 10,000,000
2. `MERCHANT_WHITELIST`: Merchant is whitelisted OR amount ≤ Rp 1,000,000
3. `DUPLICATE_CHECK`: No existing settlement for order

### 5. Settlement Bot (`services/settlementBot.ts`)

**⚠️ FULLY SIMULATED:**
- Generates mock bank reference numbers
- Marks settlements as complete
- No real fiat transfer occurs

### 6. Internal Ledger (Database)

**Real Functionality:**
- Tracks merchant balances
- Calculates platform fees (MDR)
- Records gross/net amounts

---

## 🗄️ Database Schema

```sql
-- Core order tracking
orders (order_id, merchant_id, buyer_address, amount_lsk, amount_idr, status, ...)

-- LSK → IDR conversion records
trades (trade_id, order_id, exchange, sell_amount_lsk, received_idr, ...)

-- Merchant balance tracking
merchant_ledger (merchant_id, order_id, gross_idr, platform_fee_idr, net_idr, ...)

-- Fiat payout tracking (SIMULATED)
settlements (settlement_id, order_id, payout_amount_idr, payout_reference, is_simulated, ...)

-- Rule engine audit log
rule_engine_log (order_id, rule_name, rule_passed, rule_details, final_decision, ...)
```

**Order Status Flow:**
```
PENDING → LOCKED → PAID → CONVERTING → CONVERTED → APPROVED → SETTLING → SETTLED
                                                  ↓
                                              ON_HOLD (if rules fail)
```

---

## 🚀 Running the System

### Prerequisites
- Node.js 18+
- PostgreSQL 14+
- Docker (optional)

### Setup

```bash
# Install dependencies
cd bangkingt_app_backend
npm install

# Create database
docker-compose up -d postgres

# Run migrations
psql -U qris_user -d qris_payments -f init.sql
psql -U qris_user -d qris_payments -f init_v2.sql

# Set environment variables
cp .env.example .env
# Edit .env with your config

# Start server
npm run start:server
```

### Environment Variables

```env
# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=qris_payments
DB_USER=qris_user
DB_PASSWORD=your_password

# Blockchain
LISK_RPC_URL=https://rpc.api.lisk.com
ESCROW_CONTRACT_ADDRESS=0x...  # After deployment

# Escrow wallet (for contract deployment)
ESCROW_MASTER_MNEMONIC=your_mnemonic_here
```

### Deploying the Escrow Contract

```bash
# Deploy to Lisk Mainnet
npx hardhat run scripts/deploy-escrow.js --network lisk

# Or Lisk Sepolia for testing
npx hardhat run scripts/deploy-escrow.js --network lisk-sepolia
```

---

## 📡 API Endpoints

### Create Payment Intent
```http
POST /qris/payments
Content-Type: application/json

{
  "walletAddress": "0x...",
  "qrisPayload": "00020101...",
  "amountIdr": 50000
}

Response:
{
  "success": true,
  "data": {
    "paymentId": "uuid",
    "orderId": "0x...",
    "escrowAddress": "0x...",
    "lskAmountExpected": "14.7058",
    "lskTokenAddress": "0xac485391EB2d7D88253a7F1eF18C37f4571c1A24",
    "chainId": 1135,
    "expiresAt": "2024-01-01T12:10:00Z"
  }
}
```

### Submit Transaction
```http
POST /qris/payments/:orderId/tx
Content-Type: application/json

{
  "txHash": "0x..."
}
```

### Get Payment Status
```http
GET /qris/payments/:orderId
```

### Merchant Dashboard
```http
GET /merchant/:merchantId/dashboard
```

---

## 🔒 What's Real vs Simulated

| Component | Status | Notes |
|-----------|--------|-------|
| LSK Payment | ✅ REAL | Actual on-chain transfer |
| Escrow Lock | ✅ REAL | Smart contract holds funds |
| Event Detection | ✅ REAL | Blockchain event listening |
| Price Fetch | ✅ REAL | Indodax public API |
| CEX Trade | ⚠️ MOCKED | No actual exchange trade |
| Rule Engine | ✅ REAL | Actual rule evaluation |
| Settlement | ❌ SIMULATED | No real bank transfer |
| Ledger | ✅ REAL | Accurate balance tracking |

---

## 🛤️ Path to Production

To make this production-ready:

1. **Partner with Licensed PSP**
   - Integrate with Xendit, Midtrans, or similar
   - Handle real bank transfers and e-wallet payouts

2. **Real CEX Integration**
   - Connect to Indodax, Tokocrypto, or OTC desk
   - Implement proper trade execution and monitoring

3. **Enhanced Security**
   - Multi-sig escrow
   - Rate limiting
   - KYC/AML compliance

4. **Regulatory Compliance**
   - OJK licensing for payment processing
   - Bank Indonesia approval for QRIS integration

5. **Operational**
   - 24/7 monitoring
   - Automatic reconciliation
   - Dispute resolution system

---

## 📄 License

MIT - Hackathon MVP

---

## ⚠️ Disclaimer

This is a **hackathon prototype** demonstrating the technical architecture for crypto-to-fiat payments. 

**DO NOT USE IN PRODUCTION** without:
- Proper security audits
- Regulatory compliance
- Licensed PSP integration
- Professional operational setup
