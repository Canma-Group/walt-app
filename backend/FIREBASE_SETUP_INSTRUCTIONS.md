# Firebase Realtime Database Setup - Manual Steps Required

## Status
Firebase CLI mencoba membuat Realtime Database instance tetapi gagal karena perlu setup manual di console.

## Langkah-langkah Setup

### 1. Buat Realtime Database Instance (MANUAL - Via Browser)

Browser sudah dibuka ke Firebase Console. Ikuti langkah ini:

1. **Di Firebase Console** (https://console.firebase.google.com/project/canma-wallet/database)
   - Klik **"Create Database"** untuk Realtime Database
   - Pilih location: **asia-southeast1** (Singapore - terdekat dengan Indonesia)
   - Security rules: Pilih **"Start in test mode"** untuk development
   - Klik **"Enable"**

2. **Tunggu database selesai dibuat** (~30 detik)

### 2. Deploy Rules via Firebase CLI

Setelah database dibuat, jalankan command ini:

```powershell
cd "c:\MyDream\Kandidat wallet\bangkingt_app_backend"
firebase deploy --only database
```

### 3. Verifikasi Rules

Di Firebase Console → Realtime Database → Rules tab, pastikan rules sudah ter-deploy dengan struktur:

```json
{
  "rules": {
    "near_sync": {
      "$userId": {
        ".read": true,
        ".write": "$userId === auth.uid",
        ...
      }
    }
  }
}
```

## Files yang Sudah Disiapkan

✅ `.firebaserc` - Project config (canma-wallet)
✅ `firebase.json` - Database rules config
✅ `firebase-database-rules.json` - Security rules untuk Near Sync

## Setelah Database Dibuat

Jalankan deploy command:
```powershell
firebase deploy --only database
```

Expected output:
```
✔ Deploy complete!
Database Rules for canma-wallet-default-rtdb have been updated.
```

## Test Near Sync Feature

Setelah rules ter-deploy:

1. **Run Flutter app**:
   ```powershell
   cd "c:\MyDream\Kandidat wallet\banking_app"
   flutter run
   ```

2. **Test di app**:
   - Buka app → More → Near Sync
   - Toggle "Enable Near Sync"
   - Allow location permission
   - Pastikan GPS aktif

3. **Verify di Firebase Console**:
   - Go to: Realtime Database → Data tab
   - Lihat node `/near_sync/{userId}` muncul dengan data lokasi

## Troubleshooting

**Error: "Permission denied"**
- Pastikan user sudah login/authenticated
- Check Firebase Auth di console

**Error: "Database not found"**
- Pastikan sudah create database di console
- Tunggu beberapa menit setelah create

**Location tidak update**
- Check GPS/Location services aktif di device
- Check app permissions di device settings
