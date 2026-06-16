# 🔴 Firebase Auth Error - CONFIGURATION_NOT_FOUND 400

## ❌ **Error yang Terjadi**

```
E/FirebaseAuth(21719): [GetAuthDomainTask] Error getting project config. Failed with CONFIGURATION_NOT_FOUND 400
```

## 🔍 **Penyebab Error**

Error ini terjadi karena **Firebase Authentication belum dikonfigurasi dengan benar** di Firebase Console. Ada beberapa hal yang perlu dikonfigurasi:

### **1. Firebase Authentication Belum Diaktifkan**
- Google Sign-In provider belum diaktifkan
- OAuth consent screen belum dikonfigurasi

### **2. SHA-1 Fingerprint Belum Ditambahkan**
- Android app memerlukan SHA-1 fingerprint untuk Google Sign-In
- Fingerprint belum ditambahkan ke Firebase project

### **3. OAuth Client ID Belum Dikonfigurasi**
- Web client ID belum di-setup
- Android client ID belum di-setup

---

## ✅ **Solusi - Langkah Perbaikan**

### **LANGKAH 1: Aktifkan Firebase Authentication**

1. Buka Firebase Console: https://console.firebase.google.com
2. Pilih project: **canma-wallet**
3. Pergi ke **Authentication** → **Sign-in method**
4. Klik **Google** → **Enable**
5. Pilih **Project support email**
6. Klik **Save**

### **LANGKAH 2: Tambahkan SHA-1 Fingerprint**

#### **A. Dapatkan SHA-1 Fingerprint:**

```powershell
cd "C:\MyDream\Kandidat wallet\banking_app\android"
.\gradlew signingReport
```

Atau:

```powershell
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

#### **B. Tambahkan ke Firebase:**

1. Firebase Console → **Project Settings** → **Your apps**
2. Pilih Android app (`com.bankingapp.banking_app`)
3. Scroll ke **SHA certificate fingerprints**
4. Klik **Add fingerprint**
5. Paste SHA-1 fingerprint
6. Klik **Save**

### **LANGKAH 3: Download google-services.json Baru**

1. Setelah menambahkan SHA-1, download `google-services.json` baru
2. Replace file di: `android/app/google-services.json`

### **LANGKAH 4: Verifikasi OAuth Consent Screen**

1. Buka Google Cloud Console: https://console.cloud.google.com
2. Pilih project: **canma-wallet**
3. Pergi ke **APIs & Services** → **OAuth consent screen**
4. Pastikan:
   - App name: **Canma Wallet**
   - User support email: **Your email**
   - Developer contact: **Your email**
   - Scopes: Minimal (email, profile)
5. Klik **Save and Continue**

---

## 🔧 **Quick Fix - Alternative Approach**

Jika error masih terjadi, kita bisa menambahkan error handling yang lebih baik dan fallback:

### **Option 1: Add Better Error Handling**

Tambahkan try-catch yang lebih spesifik untuk menangani error ini.

### **Option 2: Use Web3Auth Direct (Skip Firebase Auth)**

Gunakan Web3Auth langsung tanpa Firebase Auth sebagai perantara (jika memungkinkan).

---

## 📋 **Checklist Konfigurasi**

- [ ] Firebase Authentication diaktifkan
- [ ] Google Sign-In provider enabled
- [ ] SHA-1 fingerprint ditambahkan
- [ ] `google-services.json` di-update
- [ ] OAuth consent screen dikonfigurasi
- [ ] App rebuilt setelah konfigurasi

---

## 🚀 **Setelah Konfigurasi**

1. **Rebuild app:**
   ```powershell
   cd "C:\MyDream\Kandidat wallet\banking_app"
   flutter clean
   flutter pub get
   flutter run -d RRCY103SRKR
   ```

2. **Test Google Sign In:**
   - Klik "Continue with Google"
   - Pilih Google account
   - Seharusnya berhasil login

---

## ⚠️ **Catatan Penting**

- Error ini **BUKAN** error di code, tapi **konfigurasi Firebase**
- Perlu setup di Firebase Console
- SHA-1 fingerprint **WAJIB** untuk Android Google Sign-In
- Setelah konfigurasi, app perlu di-rebuild

---

**Status:** ⚠️ **PERLU KONFIGURASI FIREBASE CONSOLE**  
**Action Required:** Setup Firebase Authentication di Console 🚀

