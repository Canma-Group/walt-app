# 📱 Simulasi User Flow: Signup → Login → Password Verification → PIN Transaction

## 🎯 **Tujuan Simulasi**

Menguji end-to-end flow:
1. ✅ Membuat user baru (Signup)
2. ✅ Login dengan user baru
3. ✅ Password verification setelah login
4. ✅ PIN verification untuk transaksi

---

## 📋 **Step-by-Step Simulasi**

### **STEP 1: Signup (Membuat User Baru)**

#### 1.1. Buka Aplikasi
- Jalankan aplikasi: `flutter run`
- Aplikasi akan menampilkan **Splash Page** → **Sign In Page**

#### 1.2. Navigate ke Sign Up
- Di Sign In Page, klik **"Sign Up"** (di bagian bawah)
- Atau langsung akses: `/sign-up`

#### 1.3. Input Data Dasar
Di **Sign Up Page**, isi:
- **Full Name:** `Riyadh Lakadimu`
- **Phone Number:** `081234567890` (format: 08xx atau +62xxx)
- **Email:** `riyadhlakadimu724@gmail.com`
- Klik **"Continue"**

#### 1.4. Set Password
Di **Set Password Page**, isi:
- **Password:** `reta123` (min 8 karakter, alphanumeric)
- **Confirm Password:** `reta123`
- Password strength indicator akan muncul
- Klik **"Continue"**

#### 1.5. Set PIN
Di **Set PIN Page**, isi:
- **PIN:** `123456` (6 digits)
- **Confirm PIN:** `123456`
- Klik **"Complete Signup"**

#### 1.6. Signup Success
- User dibuat di Firebase Auth
- Data disimpan di Firestore
- PIN di-hash dan disimpan (local + Firestore)
- Password verification flag di-set (karena baru signup)
- Navigate ke **Home Page**

---

### **STEP 2: Logout (Untuk Test Password Verification)**

#### 2.1. Logout dari Aplikasi
- Klik tombol logout (jika ada di Home Page)
- Atau tutup aplikasi (swipe away)
- Password verification flag akan di-clear

---

### **STEP 3: Login dengan User Baru**

#### 3.1. Buka Aplikasi Lagi
- Aplikasi akan menampilkan **Sign In Page**

#### 3.2. Login dengan Email/Password
Di **Sign In Page**, isi:
- **Email:** `riyadhlakadimu724@gmail.com`
- **Password:** `reta123`
- Klik **"Sign In"**

#### 3.3. Login Success
- Firebase Auth akan verify email/password
- User data di-load dari Firestore
- Navigate ke **Password Verification Page** (karena flag belum verified)

---

### **STEP 4: Password Verification**

#### 4.1. Password Verification Page
- Aplikasi akan otomatis redirect ke **Password Verification Page**
- User **TIDAK BISA** bypass halaman ini

#### 4.2. Input Password
- **Password:** `reta123` (password yang sama dengan saat signup)
- Klik **"Verify Password"**

#### 4.3. Verification Success
- Password di-verify via Firebase Auth
- Password verification flag di-set
- Navigate ke **Home Page**

#### 4.4. Jika Password Salah
- Error message: **"Invalid password. Please try again."**
- User harus input password yang benar

---

### **STEP 5: PIN Verification untuk Transaksi**

#### 5.1. Trigger Transaksi
- Di Home Page, klik tombol untuk transaksi (misalnya: Transfer, Top-up, dll)
- Aplikasi akan meminta PIN verification

#### 5.2. Input PIN
- **PIN:** `123456` (PIN yang di-set saat signup)
- PIN di-verify (local check + backend check)

#### 5.3. Verification Success
- Transaksi dilanjutkan
- Jika PIN salah, transaksi dibatalkan

---

## 🔍 **Testing Checklist**

### ✅ **Signup Flow**
- [ ] Signup dengan nama, telepon, email berhasil
- [ ] Set password berhasil (min 8 chars, alphanumeric)
- [ ] Set PIN berhasil (6 digits)
- [ ] User dibuat di Firebase Auth
- [ ] Data disimpan di Firestore
- [ ] PIN di-hash dan disimpan dengan benar

### ✅ **Login Flow**
- [ ] Login dengan email/password berhasil
- [ ] User data di-load dari Firestore
- [ ] Navigate ke password verification page

### ✅ **Password Verification**
- [ ] Password verification page muncul setelah login
- [ ] Tidak bisa bypass password verification
- [ ] Password yang benar → success → navigate ke home
- [ ] Password yang salah → error message

### ✅ **PIN Verification**
- [ ] PIN verification untuk transaksi
- [ ] PIN yang benar → transaksi berhasil
- [ ] PIN yang salah → transaksi gagal

### ✅ **App Lifecycle**
- [ ] App ditutup → password verification flag cleared
- [ ] App dibuka lagi → password verification required
- [ ] Logout → password verification flag cleared

---

## 🐛 **Troubleshooting**

### **Error: "Invalid password. Please try again."**

**Kemungkinan Penyebab:**
1. Password yang diinput salah
2. User login dengan Google (tidak punya password)
3. Firebase Auth user tidak ditemukan

**Solusi:**
1. Pastikan password sama dengan saat signup
2. Untuk Google login users, perlu handling khusus (future enhancement)
3. Pastikan user sudah signup dengan email/password

### **Error: "User not found"**

**Kemungkinan Penyebab:**
1. User belum signup
2. Firebase Auth user tidak ada

**Solusi:**
1. Pastikan user sudah signup terlebih dahulu
2. Check Firebase Console → Authentication → Users

### **Error: "PIN not set"**

**Kemungkinan Penyebab:**
1. PIN belum di-set saat signup
2. PIN tidak tersimpan di Firestore

**Solusi:**
1. Pastikan PIN di-set saat signup
2. Check Firestore → users → {uid} → pin_hash dan pin_salt

---

## 📊 **Data yang Disimpan**

### **Firebase Auth:**
- Email: `riyadhlakadimu724@gmail.com`
- Password: Hashed oleh Firebase (tidak bisa diakses)
- UID: Auto-generated

### **Firestore (users/{uid}):**
```json
{
  "name": "Riyadh Lakadimu",
  "phone_number": "081234567890",
  "email": "riyadhlakadimu724@gmail.com",
  "pin_hash": "abc123...", // SHA-256 hash
  "pin_salt": "xyz789...", // Random salt
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

### **FlutterSecureStorage (Local):**
- `token`: Firebase ID Token
- `email`: User email
- `user_pin`: PIN (encrypted by OS) - untuk quick check
- `wallet_address`: Wallet address (jika ada)

---

## 🚀 **Quick Test Commands**

### **1. Check Firebase Auth Users**
```bash
# Via Firebase Console
# https://console.firebase.google.com/project/canma-wallet/authentication/users
```

### **2. Check Firestore Data**
```bash
# Via Firebase Console
# https://console.firebase.google.com/project/canma-wallet/firestore
```

### **3. Clear App Data (Untuk Test Ulang)**
```bash
# Android
adb shell pm clear com.bankingapp.banking_app

# iOS
# Uninstall dan reinstall app
```

---

## 📝 **Notes**

1. **Password Verification:**
   - Hanya berlaku untuk users yang signup dengan email/password
   - Google login users tidak memiliki password → perlu handling khusus

2. **PIN Storage:**
   - Local: FlutterSecureStorage (encrypted)
   - Backend: Firestore (hashed dengan salt)
   - Verifikasi dilakukan di client (quick) dan backend (secure)

3. **Security:**
   - Password **TIDAK** disimpan di local storage
   - PIN di-hash dengan SHA-256 + salt
   - Password verification flag cleared on app close/logout

---

**Status:** ✅ **Ready for Testing**

