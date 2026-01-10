# 🚀 Backend Run Commands - Quick Reference

## ✅ **Recommended: `npm run start`**

```powershell
cd "C:\MyDream\Kandidat wallet\bangkingt_app_backend"
npm run start
```

**What it does:**
1. Builds TypeScript (`npm run build`)
2. Starts Firebase emulators (`firebase emulators:start --only functions`)
3. Backend available at: `http://localhost:5001`

---

## 📋 **Available Scripts**

### **`npm run start`** (Recommended)
```bash
npm run build && firebase emulators:start --only functions
```
- ✅ Build TypeScript
- ✅ Start Functions emulator
- ✅ **Use this for local development!**

### **`npm run dev`** (Full Stack)
```bash
npm run build && firebase emulators:start --only functions,firestore,auth
```
- ✅ Build TypeScript
- ✅ Start Functions + Firestore + Auth emulators
- ✅ **Use this for full local testing!**

### **`npm run serve`** (Alias)
```bash
npm run start  # Same as start
```

### **`npm run build`**
```bash
tsc
```
- Compile TypeScript to JavaScript
- Output: `lib/` folder

### **`npm run build:watch`**
```bash
tsc --watch
```
- Auto-rebuild on file changes
- Useful for development

### **`npm run deploy`**
```bash
npm run build && firebase deploy --only functions
```
- Build and deploy to Firebase
- **Use this for production!**

### **`npm run logs`**
```bash
firebase functions:log
```
- View function logs from Firebase

---

## 🎯 **Workflow**

### **Local Development:**
```powershell
# Terminal 1: Start backend
cd "C:\MyDream\Kandidat wallet\bangkingt_app_backend"
npm run start

# Terminal 2: Run Flutter (in another terminal)
cd "C:\MyDream\Kandidat wallet\banking_app"
flutter run
```

### **Full Local Testing (with Firestore & Auth):**
```powershell
cd "C:\MyDream\Kandidat wallet\bangkingt_app_backend"
npm run dev
```

### **Production Deploy:**
```powershell
cd "C:\MyDream\Kandidat wallet\bangkingt_app_backend"
npm run deploy
```

---

## 🔍 **What Happens When You Run `npm run start`**

1. **Build TypeScript:**
   ```
   tsc
   → Compiles src/**/*.ts to lib/**/*.js
   ```

2. **Start Firebase Emulators:**
   ```
   firebase emulators:start --only functions
   → Functions emulator starts on port 5001
   → Backend API available at:
      http://localhost:5001/canma-wallet/us-central1/api
   ```

3. **Available Endpoints:**
   ```
   POST http://localhost:5001/canma-wallet/us-central1/api/login
   POST http://localhost:5001/canma-wallet/us-central1/api/create-qris
   GET  http://localhost:5001/canma-wallet/us-central1/api/balance/:address
   POST http://localhost:5001/canma-wallet/us-central1/api/xendit-webhook
   ```

---

## ✅ **Why `npm run start` is Better**

### **Before:**
```powershell
# Had to remember long command
firebase emulators:start --only functions
```

### **After:**
```powershell
# Simple and consistent
npm run start
```

**Benefits:**
- ✅ Shorter command
- ✅ Auto-builds TypeScript first
- ✅ Consistent with npm conventions
- ✅ Easy to remember

---

## 🧪 **Testing**

### **Test Backend is Running:**
```bash
# After running npm run start, test:
curl http://localhost:5001/canma-wallet/us-central1/api/login \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"idToken": "test"}'
```

### **Check Emulator UI:**
Open browser: http://localhost:4000

---

## 📝 **Quick Commands**

```powershell
# Start backend (recommended)
npm run start

# Start with all emulators
npm run dev

# Build only
npm run build

# Deploy to production
npm run deploy

# View logs
npm run logs
```

---

**Now you can simply use:** `npm run start` 🚀

