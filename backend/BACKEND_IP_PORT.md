# 🌐 Backend IP & PORT Information

## 📍 **Backend Location**

### **Local Development (Emulator):**

#### **IP & PORT:**
```
IP: 127.0.0.1 (localhost)
PORT: 5001
Base URL: http://127.0.0.1:5001
```

#### **Full API Endpoints:**
```
Base: http://127.0.0.1:5001/canma-wallet/us-central1/api

POST   http://127.0.0.1:5001/canma-wallet/us-central1/api/login
POST   http://127.0.0.1:5001/canma-wallet/us-central1/api/create-qris
GET    http://127.0.0.1:5001/canma-wallet/us-central1/api/balance/:walletAddress
POST   http://127.0.0.1:5001/canma-wallet/us-central1/api/xendit-webhook
GET    http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json
GET    http://127.0.0.1:5001/canma-wallet/us-central1/api/
```

#### **Emulator UI:**
```
URL: http://127.0.0.1:4000
Functions: http://127.0.0.1:4000/functions
```

---

### **Production (After Deploy):**

#### **IP & PORT:**
```
IP: Cloud (Firebase managed)
PORT: 443 (HTTPS)
Base URL: https://us-central1-canma-wallet.cloudfunctions.net/api
```

#### **Full API Endpoints:**
```
Base: https://us-central1-canma-wallet.cloudfunctions.net/api

POST   https://us-central1-canma-wallet.cloudfunctions.net/api/login
POST   https://us-central1-canma-wallet.cloudfunctions.net/api/create-qris
GET    https://us-central1-canma-wallet.cloudfunctions.net/api/balance/:walletAddress
POST   https://us-central1-canma-wallet.cloudfunctions.net/api/xendit-webhook
GET    https://us-central1-canma-wallet.cloudfunctions.net/api/swagger.json
GET    https://us-central1-canma-wallet.cloudfunctions.net/api/
```

---

## 🚀 **How to Start Backend**

### **Local Development:**
```powershell
cd "C:\MyDream\Kandidat wallet\bangkingt_app_backend"
npm run start
```

**Output:**
```
✔  functions: Emulator started at http://127.0.0.1:5001
✔  View Emulator UI at http://127.0.0.1:4000/
```

---

## 📚 **Swagger Documentation**

### **Access Swagger JSON:**
```
Local: http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json
Production: https://us-central1-canma-wallet.cloudfunctions.net/api/swagger.json
```

### **View in Swagger UI:**
1. Go to: https://editor.swagger.io
2. Click "File" → "Import URL"
3. Paste: `http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json`
4. Or use direct link: https://editor.swagger.io/?url=http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json

---

## 🧪 **Test Backend is Running**

### **Test API Info Endpoint:**
```bash
curl http://127.0.0.1:5001/canma-wallet/us-central1/api/
```

**Expected Response:**
```json
{
  "name": "Canma Wallet API",
  "version": "1.0.0",
  "description": "Lisk Crypto Banking API dengan Web3Auth + Firebase",
  "endpoints": {
    "login": "POST /login",
    "createQRIS": "POST /create-qris",
    "getBalance": "GET /balance/:walletAddress",
    "swagger": "GET /swagger.json",
    "webhook": "POST /xendit-webhook"
  },
  "documentation": "/swagger.json",
  "swaggerUI": "https://editor.swagger.io/?url=..."
}
```

### **Test Swagger Endpoint:**
```bash
curl http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json
```

---

## 📱 **Flutter Integration**

### **Update Flutter Base URL:**

**File: `banking_app/lib/config/env.dart`**
```dart
class Env {
  // Local Development
  static const String baseUrl = 'http://127.0.0.1:5001/canma-wallet/us-central1/api';
  
  // Production (uncomment when deploying)
  // static const String baseUrl = 'https://us-central1-canma-wallet.cloudfunctions.net/api';
}
```

---

## 🔍 **Troubleshooting**

### **Backend Not Starting?**
1. Check if port 5001 is available:
   ```powershell
   netstat -ano | findstr :5001
   ```
2. Kill process if needed:
   ```powershell
   taskkill /PID <PID> /F
   ```

### **Cannot Connect from Flutter?**
1. **Android Emulator:** Use `10.0.2.2` instead of `127.0.0.1`
   ```dart
   static const String baseUrl = 'http://10.0.2.2:5001/canma-wallet/us-central1/api';
   ```

2. **Physical Device:** Use your computer's local IP:
   ```powershell
   ipconfig
   # Find IPv4 Address (e.g., 192.168.1.100)
   ```
   ```dart
   static const String baseUrl = 'http://192.168.1.100:5001/canma-wallet/us-central1/api';
   ```

---

## ✅ **Summary**

| Environment | IP | PORT | Base URL |
|------------|-----|------|----------|
| **Local** | 127.0.0.1 | 5001 | http://127.0.0.1:5001/canma-wallet/us-central1/api |
| **Production** | Cloud | 443 | https://us-central1-canma-wallet.cloudfunctions.net/api |

**Swagger:** `/swagger.json`  
**API Info:** `/` (root endpoint)

---

**Status:** ✅ **READY**  
**Backend running at:** `http://127.0.0.1:5001` 🚀

