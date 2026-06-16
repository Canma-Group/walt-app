# Firebase Realtime Database Setup - Action Required

## Status: Database Instance Belum Dibuat

Firebase CLI **tidak bisa** membuat Realtime Database instance secara otomatis karena keterbatasan API.

Saya sudah membuka **Firebase Console** untuk Anda.

---

## 🔴 LANGKAH YANG HARUS ANDA LAKUKAN (5 MENIT):

### Di Browser yang Baru Dibuka:

1. **Klik tombol "Create Database"** (warna biru)
2. **Pilih location**: `asia-southeast1` (Singapore)
3. **Security rules**: Pilih **"Start in test mode"**
4. **Klik "Enable"**
5. **Tunggu ~30-60 detik** sampai status jadi "Active"

---

## ✅ SETELAH DATABASE DIBUAT

Jalankan command ini di terminal:

```powershell
cd "c:\MyDream\Kandidat wallet\bangkingt_app_backend"
firebase deploy --only database
```

**Expected Output:**
```
✔ Deploy complete!

Project Console: https://console.firebase.google.com/project/canma-wallet/overview
Hosting URL: https://canma-wallet.web.app

✔ Database Rules for canma-wallet-default-rtdb have been updated.
```

---

## 🧪 TEST NEAR SYNC FEATURE

Setelah rules ter-deploy, test di Flutter app:

```powershell
cd "c:\MyDream\Kandidat wallet\banking_app"
flutter run
```

**Di App:**
1. Tap **More** (bottom nav)
2. Tap **Near Sync**
3. Toggle **"Enable Near Sync"** → Allow location permission
4. Pastikan GPS aktif di device
5. Lihat nearby users (jika ada yang online)

**Verify di Firebase Console:**
- Go to: Database → Data tab
- Lihat node `/near_sync/{userId}` dengan data:
  ```json
  {
    "userId": "...",
    "walletAddress": "0x...",
    "name": "...",
    "latitude": -6.xxx,
    "longitude": 106.xxx,
    "lastUpdated": 1704585600000,
    "isOnline": true
  }
  ```

---

## 📋 Files yang Sudah Saya Siapkan:

✅ `.firebaserc` - Project: canma-wallet
✅ `firebase.json` - Database config
✅ `database.rules.json` - Security rules untuk Near Sync
✅ Flutter service: `near_sync_service.dart`
✅ Flutter UI: `near_sync_page.dart`
✅ Menu integration di `more_menu_sheet.dart`

---

## ❓ Troubleshooting

**"Permission denied" saat enable Near Sync**
- Check location permission di device settings
- Pastikan GPS/Location services aktif

**"No users nearby"**
- Test dengan 2 devices yang berbeda
- Pastikan kedua device sudah login dan enable Near Sync
- Check jarak antar device (max 5 km default)

**Database rules tidak ter-deploy**
- Pastikan database instance sudah dibuat di console
- Check `.firebaserc` dan `firebase.json` ada di folder backend
- Run: `firebase deploy --only database --debug` untuk detail error

---

## 🎯 Summary

**Kenapa tidak bisa full otomatis?**
Firebase Realtime Database instance creation memerlukan:
- Manual region selection
- Billing setup (meskipun free tier)
- API activation di Google Cloud

**Setelah instance dibuat**, semua update rules bisa via CLI:
```powershell
firebase deploy --only database
```

---

**Silakan buat database di console, lalu jalankan `firebase deploy --only database`!** 🚀
