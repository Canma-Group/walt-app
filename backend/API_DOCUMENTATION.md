# 📚 API Documentation - Canma Wallet Backend

## 🚀 Quick Start

### Base URL
- **Production:** `https://us-central1-canma-wallet.cloudfunctions.net/api`
- **Local:** `http://localhost:5001/canma-wallet/us-central1/api`

### Authentication
All endpoints (except `/login` and `/xendit-webhook`) require Firebase ID Token:

```
Authorization: Bearer <firebase_id_token>
```

---

## 📋 Endpoints

### **1. POST /login**

**Description:** Login dengan Web3Auth + Firebase. Endpoint utama untuk authentication.

**Request:**
```json
{
  "idToken": "eyJhbGciOiJSUzI1NiIsImtpZCI6IjE2Nz..."
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "userId": "abc123xyz",
    "email": "ellycia.alvarety@gmail.com",
    "name": "ellycia alvarety",
    "photoURL": "https://lh3.googleusercontent.com/...",
    "walletAddress": "0xB3392ec03F03F6e1dc3db76C28b7fdd14Bb43561",
    "createdAt": "2025-12-28T10:00:00.000Z",
    "lastLogin": "2025-12-28T10:00:00.000Z",
    "token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IjE2Nz..."
  }
}
```

**Error (400/401):**
```json
{
  "success": false,
  "error": "idToken is required"
}
```

**cURL Example:**
```bash
curl -X POST https://us-central1-canma-wallet.cloudfunctions.net/api/login \
  -H "Content-Type: application/json" \
  -d '{"idToken": "YOUR_FIREBASE_ID_TOKEN"}'
```

---

### **2. POST /create-qris**

**Description:** Create QRIS payment untuk top-up. Wallet address akan auto-save ke Firestore.

**Headers:**
```
Authorization: Bearer <firebase_id_token>
```

**Request:**
```json
{
  "amountInIDR": 50000,
  "userWalletAddress": "0xB3392ec03F03F6e1dc3db76C28b7fdd14Bb43561"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "qrisUrl": "00020101021226650013ID...",
    "externalId": "CANMA-abc123-1735381234",
    "amount": 50000,
    "expiresAt": "2025-12-28T11:00:00.000Z"
  }
}
```

**cURL Example:**
```bash
curl -X POST https://us-central1-canma-wallet.cloudfunctions.net/api/create-qris \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "amountInIDR": 50000,
    "userWalletAddress": "0xB3392ec03F03F6e1dc3db76C28b7fdd14Bb43561"
  }'
```

---

### **3. GET /balance/{walletAddress}**

**Description:** Get LSK balance dari blockchain.

**Headers:**
```
Authorization: Bearer <firebase_id_token>
```

**Parameters:**
- `walletAddress` (path) - Ethereum/Lisk wallet address (0x...)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "balance": "10.500000",
    "currency": "LSK",
    "walletAddress": "0xB3392ec03F03F6e1dc3db76C28b7fdd14Bb43561"
  }
}
```

**cURL Example:**
```bash
curl -X GET "https://us-central1-canma-wallet.cloudfunctions.net/api/balance/0xB3392ec03F03F6e1dc3db76C28b7fdd14Bb43561" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

### **4. POST /xendit-webhook**

**Description:** Webhook endpoint untuk Xendit payment notifications.

**Headers:**
```
x-callback-token: <webhook_secret>
```

**Request:**
```json
{
  "external_id": "CANMA-abc123-1735381234",
  "status": "COMPLETED",
  "amount": 50000
}
```

**Response (200):**
```json
{
  "success": true,
  "txHash": "0x1234...",
  "lskAmount": "10.000000"
}
```

---

## 🔐 Authentication Flow

```
1. User login dengan Google di Flutter app
2. Web3Auth generate wallet + Firebase Auth user
3. Flutter dapat Firebase ID Token
4. Flutter call POST /login dengan idToken
5. Backend verify token → create/update user
6. Backend return user data + token
7. Flutter gunakan token untuk authenticated requests
```

---

## 📊 Response Codes

| Code | Description |
|------|-------------|
| 200 | Success |
| 400 | Bad Request (invalid input) |
| 401 | Unauthorized (invalid/missing token) |
| 500 | Internal Server Error |

---

## 🧪 Testing

### Using Postman/Insomnia:

1. **Login:**
   - POST `/login`
   - Body: `{"idToken": "..."}`
   - Copy `data.token` dari response

2. **Create QRIS:**
   - POST `/create-qris`
   - Header: `Authorization: Bearer <token>`
   - Body: `{"amountInIDR": 50000, "userWalletAddress": "0x..."}`

3. **Get Balance:**
   - GET `/balance/0x...`
   - Header: `Authorization: Bearer <token>`

---

## 📖 Swagger Documentation

Full Swagger/OpenAPI spec tersedia di: `swagger.json`

**View Swagger UI:**
1. Copy `swagger.json` ke https://editor.swagger.io
2. Atau deploy ke Swagger UI server

---

## 🔒 Security Notes

- ✅ Private key **TIDAK pernah** dikirim ke backend
- ✅ Backend hanya terima wallet address (public)
- ✅ All endpoints (except `/login`) require authentication
- ✅ Webhook menggunakan signature verification

---

**Last Updated:** December 28, 2024

