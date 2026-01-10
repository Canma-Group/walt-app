# 🔧 Script untuk Mendapatkan SHA-1 Fingerprint

## 📋 **Cara Mendapatkan SHA-1 Fingerprint**

### **Method 1: Menggunakan Gradle (Recommended)**

```powershell
cd "C:\MyDream\Kandidat wallet\banking_app\android"
.\gradlew signingReport
```

**Output akan menampilkan:**
```
Variant: debug
Config: debug
Store: C:\Users\riyadh\.android\debug.keystore
Alias: AndroidDebugKey
SHA1: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
```

**Copy SHA1 value** (tanpa spasi, format: `XX:XX:XX:...`)

---

### **Method 2: Menggunakan Keytool**

```powershell
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

**Cari baris:**
```
SHA1: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
```

---

## 🔗 **Langkah Menambahkan ke Firebase**

1. **Buka Firebase Console:**
   - https://console.firebase.google.com/project/canma-wallet/settings/general

2. **Scroll ke "Your apps" → Android app**

3. **Klik "Add fingerprint"**

4. **Paste SHA-1 fingerprint** (format: `XX:XX:XX:...`)

5. **Klik "Save"**

6. **Download `google-services.json` baru**

7. **Replace file:**
   - `android/app/google-services.json`

8. **Rebuild app:**
   ```powershell
   flutter clean
   flutter pub get
   flutter run -d RRCY103SRKR
   ```

---

## ✅ **Verification**

Setelah menambahkan SHA-1, error `CONFIGURATION_NOT_FOUND` seharusnya hilang.

---

**File:** `GET_SHA1_FINGERPRINT.md`

