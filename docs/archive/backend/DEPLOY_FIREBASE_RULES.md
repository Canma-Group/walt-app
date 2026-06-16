# Deploy Firebase Realtime Database Rules

## Langkah-langkah Deploy Rules untuk Near Sync Feature

### Opsi 1: Via Firebase Console (Recommended)

1. **Buka Firebase Console**
   - Go to: https://console.firebase.google.com/
   - Pilih project: `canma-wallet`

2. **Navigate ke Realtime Database**
   - Di sidebar kiri, klik **Build** → **Realtime Database**
   - Jika belum ada database, klik **Create Database**
   - Pilih location: `us-central1` (atau sesuai preferensi)
   - Start in **test mode** dulu untuk development

3. **Deploy Rules**
   - Klik tab **Rules** di Realtime Database
   - Copy-paste isi dari file `firebase-database-rules.json`
   - Klik **Publish**

### Opsi 2: Via Firebase CLI

1. **Install Firebase CLI** (jika belum)
   ```bash
   npm install -g firebase-tools
   ```

2. **Login ke Firebase**
   ```bash
   firebase login
   ```

3. **Initialize Firebase di project** (jika belum)
   ```bash
   cd "c:\MyDream\Kandidat wallet\bangkingt_app_backend"
   firebase init database
   ```
   - Pilih existing project: `canma-wallet`
   - Database rules file: `firebase-database-rules.json`

4. **Deploy Rules**
   ```bash
   firebase deploy --only database
   ```

### Verifikasi Rules Berhasil

1. Di Firebase Console → Realtime Database → Rules
2. Pastikan rules sudah sesuai dengan file `firebase-database-rules.json`
3. Test dengan write data:
   ```
   /near_sync/{userId}
   ```

### Rules Summary

Rules yang di-deploy akan:
- ✅ Allow semua user **read** data di `/near_sync`
- ✅ Allow user hanya **write** ke entry milik mereka sendiri
- ✅ Validasi struktur data (latitude, longitude, timestamp, dll)
- ✅ Indexing untuk query berdasarkan `lastUpdated`, `latitude`, `longitude`

### Troubleshooting

**Error: Permission denied**
- Pastikan user sudah authenticated dengan Firebase Auth
- Check `auth.uid` di rules

**Error: Data validation failed**
- Pastikan semua required fields ada: `userId`, `walletAddress`, `latitude`, `longitude`, `lastUpdated`, `isOnline`
- Check format data (latitude: -90 to 90, longitude: -180 to 180)

**Database tidak muncul**
- Pastikan Firebase Realtime Database sudah di-enable di project
- Create database dulu via console jika belum ada
