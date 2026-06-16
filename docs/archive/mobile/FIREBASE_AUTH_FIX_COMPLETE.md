# ✅ Firebase Auth Error - SOLUSI LENGKAP

## 🔴 **Error yang Terjadi**

```
E/FirebaseAuth(21719): [GetAuthDomainTask] Error getting project config. Failed with CONFIGURATION_NOT_FOUND 400
```

**Penyebab:** Firebase Authentication belum dikonfigurasi dengan benar di Firebase Console.

---

## 🔑 **SHA-1 Fingerprint Anda**

```
30:40:D2:53:2A:B9:25:35:97:2F:92:13:0F:EA:4A:18:2A:1F:21:BA
```

**Copy fingerprint di atas** untuk ditambahkan ke Firebase Console.

---

## 📋 **Langkah Perbaikan (Step by Step)**

### **STEP 1: Aktifkan Firebase Authentication**

1. Buka: https://console.firebase.google.com/project/canma-wallet/authentication/providers
2. Klik **"Get started"** (jika pertama kali)
3. Klik **"Google"** provider
4. **Enable** Google Sign-In
5. Pilih **Project support email** (email Anda)
6. Klik **"Save"**

---

### **STEP 2: Tambahkan SHA-1 Fingerprint**

1. Buka: https://console.firebase.google.com/project/canma-wallet/settings/general
2. Scroll ke bagian **"Your apps"**
3. Klik pada **Android app** (`com.bankingapp.banking_app`)
4. Scroll ke **"SHA certificate fingerprints"**
5. Klik **"Add fingerprint"**
6. Paste SHA-1 fingerprint:
   ```
   30:40:D2:53:2A:B9:25:35:97:2F:92:13:0F:EA:4A:18:2A:1F:21:BA
   ```
7. Klik **"Save"**

---

### **STEP 3: Download google-services.json Baru**

1. Setelah menambahkan SHA-1, **download `google-services.json` baru**
2. Klik **"Download google-services.json"** di halaman yang sama
3. **Replace** file di: `android/app/google-services.json`

---

### **STEP 4: Konfigurasi OAuth Consent Screen (Google Cloud)**

1. Buka: https://console.cloud.google.com/apis/credentials/consent?project=canma-wallet
2. Pilih **"External"** (untuk testing)
3. Isi:
   - **App name:** Canma Wallet
   - **User support email:** Email Anda
   - **Developer contact:** Email Anda
4. Klik **"Save and Continue"**
5. **Scopes:** Klik "Save and Continue" (default sudah cukup)
6. **Test users:** Tambahkan email Anda (opsional)
7. Klik **"Save and Continue"** → **"Back to Dashboard"**

---

### **STEP 5: Rebuild Aplikasi**

```powershell
cd "C:\MyDream\Kandidat wallet\banking_app"
flutter clean
flutter pub get
flutter run -d RRCY103SRKR
```

---

## ✅ **Verification Checklist**

Setelah semua langkah di atas:

- [ ] Firebase Authentication diaktifkan
- [ ] Google Sign-In provider enabled
- [ ] SHA-1 fingerprint ditambahkan: `30:40:D2:53:2A:B9:25:35:97:2F:92:13:0F:EA:4A:18:2A:1F:21:BA`
- [ ] `google-services.json` di-update
- [ ] OAuth consent screen dikonfigurasi
- [ ] App di-rebuild

---

## 🧪 **Testing**

Setelah rebuild:

1. **Buka app**
2. **Klik "Continue with Google"**
3. **Pilih Google account**
4. **Seharusnya berhasil login** ✅

---

## 🔧 **Code Changes Made**

### **Error Handling Improved:**
- ✅ Added specific error handling untuk `CONFIGURATION_NOT_FOUND`
- ✅ Error message lebih informatif dengan instruksi perbaikan
- ✅ User akan mendapat petunjuk jelas jika konfigurasi belum selesai

**File Updated:**
- `lib/services/web3auth_service.dart` - Better error handling

---

## ⚠️ **Jika Masih Error**

### **Check 1: Verifikasi SHA-1 Sudah Ditambahkan**
- Pastikan SHA-1 sudah muncul di Firebase Console
- Pastikan format benar (dengan `:`)

### **Check 2: Verifikasi google-services.json**
- Pastikan file sudah di-replace dengan yang baru
- Pastikan file ada di `android/app/google-services.json`

### **Check 3: Verifikasi OAuth Consent Screen**
- Pastikan sudah dikonfigurasi di Google Cloud Console
- Pastikan app name dan email sudah diisi

### **Check 4: Rebuild App**
- Pastikan sudah `flutter clean` sebelum rebuild
- Pastikan sudah `flutter pub get`

---

## 📚 **Dokumentasi Terkait**

1. `FIREBASE_AUTH_ERROR_FIX.md` - Penjelasan error
2. `GET_SHA1_FINGERPRINT.md` - Cara mendapatkan SHA-1
3. `FIREBASE_NEXT_STEPS.md` - Next steps setelah konfigurasi

---

## 🎯 **Summary**

**Error:** `CONFIGURATION_NOT_FOUND 400`  
**Penyebab:** Firebase Authentication belum dikonfigurasi  
**Solusi:** Setup di Firebase Console + Tambah SHA-1  
**SHA-1:** `30:40:D2:53:2A:B9:25:35:97:2F:92:13:0F:EA:4A:18:2A:1F:21:BA`

**Status:** ⚠️ **PERLU SETUP FIREBASE CONSOLE**  
**Action:** Ikuti 5 langkah di atas 🚀

---

**Setelah setup selesai, error akan hilang dan Google Sign In akan berfungsi!** ✅

