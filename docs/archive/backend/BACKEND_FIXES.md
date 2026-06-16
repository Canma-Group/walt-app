# ✅ Backend Fixes Applied

## 🔧 **Errors Fixed**

### **1. Maximum Call Stack Size Exceeded**
**Error:**
```
RangeError: Maximum call stack size exceeded
at extractStack (firebase-functions/lib/runtime/loader.js:83:13)
```

**Cause:**
- Circular dependency antara `index.ts` dan `config/firebase.ts`
- Duplicate export `db` dan `auth`

**Fix:**
- ✅ Removed duplicate exports from `index.ts`
- ✅ Fixed `config/firebase.ts` to check if admin is initialized
- ✅ Use direct `admin.firestore()` in `index.ts` to avoid circular import

### **2. Xendit API Key Warning**
**Warning:**
```
⚠️ Xendit API key not properly configured. Using development mode.
```

**Status:**
- ✅ Not critical for development
- ✅ Backend will work with mock data
- ⚠️ Configure `XENDIT_API_KEY` in `.env` for production

---

## 🆕 **New Features Added**

### **1. Swagger Endpoint**
```
GET /swagger.json
```
- Returns OpenAPI 3.0 specification
- Auto-updates server URL based on environment

### **2. API Info Endpoint**
```
GET /
```
- Returns API information
- Lists all available endpoints
- Provides Swagger UI link

---

## 📍 **Backend IP & PORT**

### **Local Development:**
```
IP: 127.0.0.1
PORT: 5001
Base URL: http://127.0.0.1:5001/canma-wallet/us-central1/api
```

### **Available Endpoints:**
```
GET  /                          → API info
GET  /swagger.json              → Swagger documentation
POST /login                     → Web3Auth + Firebase login
POST /create-qris               → Create QRIS payment
GET  /balance/:walletAddress    → Get LSK balance
POST /xendit-webhook            → Xendit webhook handler
```

### **Emulator UI:**
```
URL: http://127.0.0.1:4000
```

---

## 🚀 **How to Start**

```powershell
cd "C:\MyDream\Kandidat wallet\bangkingt_app_backend"
npm run start
```

**Expected Output:**
```
✔  functions: Emulator started at http://127.0.0.1:5001
✔  View Emulator UI at http://127.0.0.1:4000/
```

---

## 🧪 **Test Backend**

### **1. Test API Info:**
```bash
curl http://127.0.0.1:5001/canma-wallet/us-central1/api/
```

### **2. Test Swagger:**
```bash
curl http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json
```

### **3. View in Browser:**
- API Info: http://127.0.0.1:5001/canma-wallet/us-central1/api/
- Swagger: http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json
- Swagger UI: https://editor.swagger.io/?url=http://127.0.0.1:5001/canma-wallet/us-central1/api/swagger.json

---

## ✅ **Verification**

### **Build Status:**
```bash
npm run build
# ✅ TypeScript compiles successfully
```

### **Backend Status:**
```bash
npm run start
# ✅ Emulator starts without errors
# ✅ No more "Maximum call stack size exceeded"
```

---

## 📚 **Documentation**

1. **`BACKEND_IP_PORT.md`** - Complete IP & PORT information
2. **`swagger.json`** - OpenAPI 3.0 specification
3. **`API_DOCUMENTATION.md`** - API documentation

---

**Status:** ✅ **ALL ERRORS FIXED**  
**Backend:** ✅ **RUNNING AT http://127.0.0.1:5001**  
**Swagger:** ✅ **AVAILABLE AT /swagger.json**

Ready to use! 🚀

