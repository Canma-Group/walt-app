# 🔄 Fix: Aplikasi Mutar-Mutar Setelah Login Google

## 🔴 **Masalah**

Aplikasi stuck di loading (mutar-mutar) setelah user memilih akun Google untuk login.

---

## 🔍 **Penyebab yang Mungkin**

### **1. Web3Auth Client ID Belum Dikonfigurasi** ⚠️ **PALING MUNGKIN**
- File `lib/config/env.dart` masih menggunakan placeholder: `YOUR_WEB3AUTH_CLIENT_ID`
- Web3Auth initialization akan gagal tanpa Client ID yang valid

### **2. Web3Auth Login Timeout**
- Koneksi internet lambat
- Web3Auth server tidak merespons
- Firebase JWT token tidak valid

### **3. Wallet Address Extraction Gagal**
- Web3Auth response tidak mengandung wallet address
- Error tidak di-catch dengan baik

### **4. Error Tidak Ditampilkan ke User**
- Error terjadi tapi tidak muncul di UI
- User hanya melihat loading spinner

---

## ✅ **Perbaikan yang Sudah Dilakukan**

### **1. Added Debug Logging**
- ✅ Logging di setiap step login flow
- ✅ Error logging dengan stack trace
- ✅ Logging untuk debugging

### **2. Added Timeout Handling**
- ✅ Timeout 30 detik untuk Google Sign-In
- ✅ Timeout 10 detik untuk ID Token
- ✅ Timeout 30 detik untuk Web3Auth login
- ✅ Timeout 60 detik untuk overall login flow

### **3. Improved Error Handling**
- ✅ Check Web3Auth Client ID configuration
- ✅ Better error messages
- ✅ Error ditampilkan ke user via snackbar

### **4. Improved Wallet Address Extraction**
- ✅ Try multiple fields: `dappShare`, `verifierId`, `email`, `name`
- ✅ Fallback jika wallet address tidak ditemukan

---

## 🚀 **Langkah Perbaikan**

### **STEP 1: Konfigurasi Web3Auth Client ID** ⚠️ **WAJIB**

1. **Buka Web3Auth Dashboard:**
   - https://dashboard.web3auth.io

2. **Login atau Sign Up**

3. **Buat Project Baru:**
   - Klik "Create Project"
   - Nama: "Canma Wallet"
   - Network: **Testnet** (untuk development)

4. **Setup Custom Auth (JWT):**
   - Pilih "Custom Auth" → "JWT"
   - Verifier Name: `canma-wallet` (harus sama dengan domain di code)
   - Domain: `canma-wallet` (atau sesuai kebutuhan)

5. **Copy Client ID:**
   - Setelah project dibuat, copy **Client ID**
   - Format: `BPxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

6. **Update `lib/config/env.dart`:**
   ```dart
   static const String web3AuthClientId = 'BPxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
   ```

7. **Rebuild App:**
   ```powershell
   cd "C:\MyDream\Kandidat wallet\banking_app"
   flutter clean
   flutter pub get
   flutter run -d RRCY103SRKR
   ```

---

### **STEP 2: Check Logs**

Setelah rebuild, coba login lagi dan check logs di terminal:

```
[Web3Auth] Starting Google login...
[Web3Auth] Signing in with Google provider...
[Web3Auth] Google sign-in successful
[Web3Auth] Firebase user: user@example.com
[Web3Auth] Getting Firebase ID token...
[Web3Auth] ID token obtained, length: 1234
[Web3Auth] Logging in to Web3Auth with JWT...
[Web3Auth] Web3Auth login response received
[Web3Auth] Private key: 0x1234567890...
[Web3Auth] Wallet address: 0x...
[Web3Auth] Session saved successfully
[AuthService] Login successful!
```

**Jika ada error, akan muncul di logs!**

---

### **STEP 3: Verifikasi Error**

Jika masih stuck, check:

1. **Web3Auth Client ID:**
   - Pastikan sudah di-update di `env.dart`
   - Pastikan tidak ada typo

2. **Web3Auth Verifier:**
   - Verifier name harus sama dengan `domain` di code
   - Default: `canma-wallet`

3. **Firebase Auth:**
   - Pastikan Google Sign-In sudah diaktifkan
   - Pastikan SHA-1 sudah ditambahkan

4. **Network:**
   - Pastikan koneksi internet stabil
   - Coba dengan WiFi atau mobile data

---

## 🐛 **Debugging**

### **Check Logs di Terminal:**

Setelah login, scroll ke atas di terminal Flutter dan cari:
- `[Web3Auth]` - Log dari Web3Auth service
- `[AuthService]` - Log dari Auth service
- `[AuthBloc]` - Log dari Auth BLoC

**Error akan muncul di logs!**

### **Common Errors:**

1. **"Web3Auth Client ID belum dikonfigurasi"**
   - **Fix:** Update `lib/config/env.dart` dengan Client ID yang valid

2. **"Web3Auth login timeout"**
   - **Fix:** Check koneksi internet, coba lagi

3. **"Failed to get private key from Web3Auth"**
   - **Fix:** Check Web3Auth dashboard, pastikan verifier sudah dikonfigurasi

4. **"Firebase Auth user not found"**
   - **Fix:** Pastikan Google Sign-In berhasil

---

## 📋 **Checklist**

- [ ] Web3Auth Client ID sudah dikonfigurasi
- [ ] Web3Auth project sudah dibuat di dashboard
- [ ] Custom Auth (JWT) verifier sudah setup
- [ ] Verifier name = `canma-wallet`
- [ ] Firebase Google Sign-In sudah diaktifkan
- [ ] SHA-1 fingerprint sudah ditambahkan
- [ ] `google-services.json` sudah di-update
- [ ] App sudah di-rebuild setelah konfigurasi

---

## 🎯 **Summary**

**Masalah:** Aplikasi stuck di loading setelah login Google  
**Penyebab Utama:** Web3Auth Client ID belum dikonfigurasi  
**Solusi:** Setup Web3Auth project dan update Client ID  

**Status:** ✅ **CODE FIXED** - Perlu konfigurasi Web3Auth Client ID  
**Action:** Ikuti STEP 1 di atas 🚀

---

**Setelah Web3Auth Client ID dikonfigurasi, login akan berfungsi dengan baik!** ✅

