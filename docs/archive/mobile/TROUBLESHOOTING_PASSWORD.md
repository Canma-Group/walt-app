# 🔧 Troubleshooting: Password Verification Error

## ❌ **Error: "Password reta123 salah"**

### **Kemungkinan Penyebab:**

1. **User belum signup dengan password tersebut**
   - Password "reta123" hanya contoh dari dokumentasi
   - User harus signup terlebih dahulu dengan password yang diinginkan

2. **Password yang digunakan saat signup berbeda**
   - Password yang diinput di password verification harus sama dengan password saat signup
   - Pastikan tidak ada typo atau spasi

3. **User login dengan Google (bukan email/password)**
   - Jika user login dengan Google, tidak ada password
   - Password verification akan di-skip untuk Google users

4. **User belum signup sama sekali**
   - User harus signup terlebih dahulu sebelum bisa login

---

## ✅ **Solusi:**

### **1. Pastikan User Sudah Signup**

**Langkah-langkah:**
1. Buka aplikasi
2. Klik **"Sign Up"**
3. Input data:
   - Name: `Riyadh Lakadimu`
   - Phone: `081234567890`
   - Email: `riyadhlakadimu724@gmail.com`
4. Set Password: `reta123` (atau password lain yang diinginkan)
5. Set PIN: `123456`
6. Complete Signup

### **2. Gunakan Password yang Sama**

**Saat Password Verification:**
- Gunakan password yang **sama persis** dengan saat signup
- Pastikan tidak ada spasi di awal/akhir
- Case-sensitive (huruf besar/kecil harus sama)

**Contoh:**
- Signup password: `reta123`
- Verification password: `reta123` ✅
- Verification password: `Reta123` ❌ (case berbeda)
- Verification password: `reta123 ` ❌ (ada spasi)

### **3. Check User di Firebase Console**

**Cara check:**
1. Buka: https://console.firebase.google.com/project/canma-wallet/authentication/users
2. Cari email user
3. Check provider:
   - **password** = User signup dengan email/password
   - **google.com** = User login dengan Google (tidak punya password)

### **4. Reset Password (Jika Lupa)**

**Jika lupa password:**
1. Di Sign In page, klik **"Forgot Password"** (jika ada)
2. Atau buat user baru dengan email berbeda
3. Atau reset password via Firebase Console

---

## 🔍 **Debug Steps:**

### **Step 1: Check Apakah User Sudah Signup**
```bash
# Check di Firebase Console
# Authentication → Users → Cari email user
```

### **Step 2: Check Provider**
- Jika provider = **password** → User punya password
- Jika provider = **google.com** → User tidak punya password

### **Step 3: Test Login**
1. Coba login dengan email/password
2. Jika login berhasil → Password benar
3. Jika login gagal → Password salah atau user belum signup

### **Step 4: Test Password Verification**
1. Setelah login, akan muncul Password Verification page
2. Input password yang sama dengan saat signup
3. Jika error → Password salah atau typo

---

## 📝 **Catatan Penting:**

1. **Password tidak bisa dilihat**
   - Password disimpan di Firebase Auth (hashed)
   - Tidak bisa di-recover atau dilihat
   - Jika lupa, harus reset password

2. **Google Login Users**
   - User yang login dengan Google tidak punya password
   - Password verification akan di-skip otomatis
   - User langsung masuk ke Home

3. **Password Verification Flow**
   - Setelah login → Password Verification page
   - Input password yang sama dengan saat signup
   - Jika benar → Home page
   - Jika salah → Error message

---

## 🚀 **Quick Fix:**

### **Jika Password Selalu Salah:**

1. **Buat User Baru:**
   - Signup dengan email baru
   - Set password yang mudah diingat (misalnya: `test1234`)
   - Set PIN: `123456`

2. **Login dengan User Baru:**
   - Email: email yang baru dibuat
   - Password: password yang baru dibuat

3. **Password Verification:**
   - Input password yang sama dengan saat signup

---

**Status:** ✅ **Fixed - Password verification sekarang handle Google users dan memberikan error message yang lebih jelas**

