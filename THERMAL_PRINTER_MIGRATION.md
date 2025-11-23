# Thermal Printer Feature Migration Guide

Panduan ini merangkum seluruh komponen yang harus Anda salin dan sesuaikan ketika memindahkan fitur Bluetooth thermal printer dari proyek ini ke proyek Flutter lain.

---

## 1. Dependensi & Konfigurasi Proyek

| File/Bagian | Tindakan |
|-------------|---------|
| `pubspec.yaml` | Salin constraint Flutter/Dart lalu tambahkan dependency berikut: `blue_thermal_printer`, `provider`, serta paket UI lain yang digunakan. Setelah itu jalankan `flutter pub get`. |
| `analysis_options.yaml` (opsional) | Salin bila ingin aturan linting yang sama. |
| `.gitignore`, `.metadata` (opsional) | Tidak wajib, tetapi berguna untuk menjaga struktur yang konsisten. |

> **Catatan:** Setelah memodifikasi `pubspec.yaml`, lakukan `flutter clean && flutter pub get` agar cache plugin diperbarui di proyek baru.

---

## 2. Kode Dart

### a. Service Bluetooth
- File: `lib/services/bluetooth_printer_service.dart`.
- Tanggung jawab: manajemen perangkat bonding/discovery, koneksi, heartbeat, reset hasil, hingga penyimpanan error.
- Sesuaikan import path sesuai struktur baru.
- Inisialisasi di `main()` menggunakan state management (mis. `ChangeNotifierProvider`).

### b. UI & Logika Presentasi
- File utama saat ini: `lib/main.dart`.
- Komponen penting yang perlu ikut:
  - `PrinterHomePage`, `_ConnectionOverview`, `_TestPrintCard`, `_ErrorCard`.
  - `BluetoothDiscoveryPage`, `_ScanHeader`, `_DiscoveredSection`, `_DeviceTile`, `_DiscoveryPlaceholder`, `_BluetoothOffBanner`, `_StatusChip`, `_NewBadge`.
- Anda bebas memecah widget ke file berbeda selama tetap memanggil API `BluetoothPrinterManager` yang sama.

### c. Integrasi Provider
- Bungkus root app dengan `ChangeNotifierProvider(create: (_) => BluetoothPrinterManager())` atau adapter state management pilihan Anda.
- Pastikan halaman lain menggunakan `context.watch` / `read` sesuai kebutuhan.

---

## 3. Android Native Layer

### a. MainActivity
- File: `android/app/src/main/kotlin/com/example/test_print_thermal/MainActivity.kt`.
- Salin seluruh isi, lalu:
  - Ubah deklarasi package (`package ...`) agar cocok dengan package proyek baru.
  - Jika ingin mengganti nama channel, perbarui konstanta di Dart (`BluetoothPrinterManager` → `_scanChannel`, `_scanEvents`, `_adapterStateEvents`).
- Peran file ini:
  - Menyediakan `MethodChannel` untuk `startDiscovery`, `stopDiscovery`, `getDiscoveredDevices`, `getAdapterState`.
  - Menyediakan `EventChannel` untuk event discovery dan status adapter.
  - Mengelola permission (BLUETOOTH/Lokasi) dan BroadcastReceiver.

### b. Android Manifest & Permission
- File: `android/app/src/main/AndroidManifest.xml`.
- Pastikan permission berikut tersedia dan disesuaikan dengan minSdk Anda:
  - `<uses-permission android:name="android.permission.BLUETOOTH"/>`
  - `<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>`
  - `<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />`
  - `<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" tools:targetApi="s" />`
  - `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>`
  - `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>`
- Tambahkan `<uses-feature android:name="android.hardware.bluetooth" android:required="false"/>` bila diperlukan.

### c. Gradle Konfigurasi
- `android/app/build.gradle.kts`
  - Atur `namespace`, `applicationId`, `compileSdk`, `targetSdk`, `minSdk`, dan `ndkVersion = "27.0.12077973"` atau versi yang tersedia di mesin Anda.
  - Pastikan `kotlinOptions.jvmTarget = "11"` serta plugin Kotlin diterapkan.
- `android/build.gradle.kts`
  - Sertakan blok berikut untuk memastikan plugin `blue_thermal_printer` memiliki namespace saat build:
    ```kotlin
    subprojects {
        if (name == "blue_thermal_printer") {
            pluginManager.withPlugin("com.android.library") {
                extensions.configure(LibraryExtension::class.java) {
                    if (namespace.isNullOrBlank()) {
                        namespace = "id.kakzaki.blue_thermal_printer"
                    }
                }
            }
        }
    }
    ```
  - Pastikan repositori `google()` dan `mavenCentral()` aktif di seluruh subproject.

### d. NDK dan SDK
- Install NDK versi yang dirujuk (`27.0.12077973`) melalui Android Studio SDK Manager.
- Jika memakai versi berbeda, ubah `ndkVersion` di `build.gradle.kts` agar cocok.

---

## 4. iOS / macOS (Opsional)
- Tidak ada kode native khusus, tetapi plugin tetap memerlukan izin.
- Tambahkan key berikut pada `ios/Runner/Info.plist` jika menargetkan iOS:
  - `NSBluetoothAlwaysUsageDescription`
  - `NSBluetoothPeripheralUsageDescription` (untuk kompatibilitas versi lama)
  - `NSLocationWhenInUseUsageDescription` bila scanning memerlukan lokasi.
- Jalankan `cd ios && pod install` setelah `flutter pub get` untuk memastikan plugin terpasang.

---

## 5. Langkah Migrasi Cepat

1. **Salin file konfigurasi** (`pubspec.yaml`, `analysis_options.yaml` bila perlu) lalu jalankan `flutter pub get`.
2. **Tambahkan service & UI Dart** (`lib/services/...` dan widget di `lib/main.dart`).
3. **Integrasikan provider** di `main()` proyek baru.
4. **Copy MainActivity** dan sesuaikan package + channel.
5. **Perbarui manifest & gradle** sesuai daftar pada Bagian 3.
6. **Tambahkan izin iOS** bila target multi-platform.
7. Jalankan `flutter clean`, lalu `flutter run` di perangkat fisik untuk verifikasi scanning, koneksi, dan test print.

Dengan mengikuti checklist di atas, Anda dapat memindahkan seluruh fitur thermal printer (discovery, reset hasil, status Bluetooth, koneksi, dan test print) ke proyek manapun tanpa kehilangan fungsionalitas penting.
