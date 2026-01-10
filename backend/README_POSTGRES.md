# QRIS Payment Backend - PostgreSQL Setup

Backend untuk QRIS payment system tanpa Firebase billing, menggunakan Express + PostgreSQL + Docker.

## 🚀 Quick Start

### 1. Setup Environment Variables

Copy `.env.example` ke `.env`:
```bash
cp .env.example .env
```

Edit `.env` dan isi:
```bash
# Database (default sudah OK untuk Docker)
DB_HOST=localhost
DB_PORT=5432
DB_NAME=qris_payments
DB_USER=qris_user
DB_PASSWORD=qris_password_dev

# Server
PORT=3000

# PENTING: Generate mnemonic baru di https://iancoleman.io/bip39/
# Pilih 24 words, copy hasil BIP39 Mnemonic
ESCROW_MASTER_MNEMONIC=ranch bind announce review scatter defy crystal helmet rule powder wasp live note paper setup must company thunder click dry skill this board season
```

### 2. Start PostgreSQL dengan Docker

```bash
npm run docker:up
```

Cek logs database:
```bash
npm run docker:logs
```

### 3. Build & Start Server

```bash
npm run build
npm start
```

Server akan running di: **http://localhost:3000**

## 📋 API Endpoints

### Health Check
```bash
GET http://localhost:3000/health
```

### Create Payment Intent
```bash
POST http://localhost:3000/qris/payments
Content-Type: application/json

{
  "walletAddress": "0x1234...",
  "qrisPayload": "00020101021226...",
  "amountIdr": 50000
}
```

Response:
```json
{
  "success": true,
  "data": {
    "paymentId": "uuid",
    "escrowAddress": "0xabc...",
    "amountIdr": 50000,
    "lskAmountExpected": "263.15789474",
    "lskTokenAddress": "0xac485391EB2d7D88253a7F1eF18C37f4571c1A24",
    "chainId": 1135,
    "expiresAt": "2026-01-01T14:10:00.000Z"
  }
}
```

### Get Payment Status
```bash
GET http://localhost:3000/qris/payments/:paymentId
```

### Submit Transaction Hash
```bash
POST http://localhost:3000/qris/payments/:paymentId/tx
Content-Type: application/json

{
  "txHash": "0xabc123..."
}
```

## 🗄️ Database Schema

Table: `payment_intents`
- `payment_id` (UUID, PK)
- `created_at`, `expires_at`, `updated_at`
- `payer_wallet_address` (VARCHAR 42)
- `qris_payload`, `qris_hash`
- `merchant_name`
- `amount_idr` (DECIMAL)
- `lsk_amount_expected`, `lsk_amount_expected_wei`
- `escrow_address` (VARCHAR 42)
- `status` (CREATED | TX_SUBMITTED | PAID | EXPIRED | FAILED)
- `tx_hash`, `verified_at`, `receipt_id`, `ledger_tx_hash`

## 🔄 Auto-Verification

Backend otomatis polling Blockscout API setiap 10 detik untuk verifikasi deposit LSK ke escrow address.

Saat transfer terdeteksi:
- Status berubah jadi `PAID`
- `receipt_id` di-generate
- `verified_at` timestamp di-set

## 🛠️ Development Commands

```bash
# Build TypeScript
npm run build

# Build + watch mode
npm run build:watch

# Start server
npm start

# Docker commands
npm run docker:up      # Start PostgreSQL
npm run docker:down    # Stop PostgreSQL
npm run docker:logs    # View logs
```

## 🐳 Docker Compose

PostgreSQL container:
- Image: `postgres:15-alpine`
- Port: `5432`
- Database: `qris_payments`
- User: `qris_user`
- Password: `qris_password_dev`

Data disimpan di Docker volume: `postgres_data`

## 🔐 Security Notes

- **Jangan commit `.env`** ke git
- Mnemonic di `.env` hanya untuk **demo/hackathon**
- Untuk production: gunakan secret manager
- Database password harus diganti di production

## 📝 Notes

- Backend ini **tidak butuh Firebase billing**
- Semua data payment disimpan di PostgreSQL
- Deposit verifier running otomatis saat server start
- Escrow address unik per payment (HD wallet derivation)

## 🐛 Troubleshooting

### Database connection error
```bash
# Cek Docker container running
docker ps

# Restart database
npm run docker:down
npm run docker:up
```

### Mnemonic error
Pastikan mnemonic di `.env` adalah **12 atau 24 kata** yang valid dari https://iancoleman.io/bip39/

### Port already in use
Ubah `PORT` di `.env` atau kill process:
```bash
# Windows
netstat -ano | findstr :3000
taskkill /PID <PID> /F
```
