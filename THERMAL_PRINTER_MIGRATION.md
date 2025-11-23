# Thermal Printer Feature Migration Guide

Panduan ini merangkum seluruh komponen yang harus Anda salin dan sesuaikan ketika memindahkan fitur Bluetooth thermal printer dari proyek ini ke proyek Flutter lain.

---

## 1. Dependensi & Konfigurasi Proyek

| File/Bagian | Tindakan |
|-------------|---------|
| `pubspec.yaml` | Salin constraint Flutter/Dart lalu tambahkan dependency berikut: `blue_thermal_printer`, `provider`, `intl` (jika ingin format tanggal sama), dan paket UI lain yang digunakan. Setelah itu jalankan `flutter pub get`. |
| `analysis_options.yaml` (opsional) | Salin bila ingin aturan linting yang sama. |
| `.gitignore`, `.metadata` (opsional) | Tidak wajib, tetapi berguna untuk menjaga struktur yang konsisten. |
| `README.md` (opsional) | Perbarui dokumentasi proyek baru berdasarkan panduan ini agar tim lain mengetahui dependensi tambahan. |

> **Catatan:** Setelah memodifikasi `pubspec.yaml`, lakukan `flutter clean && flutter pub get` agar cache plugin diperbarui di proyek baru.

---

## 2. Kode Dart

### a. Service Bluetooth
- File sumber: `lib/services/bluetooth_printer_service.dart`.
- Tanggung jawab: manajemen perangkat bonding/discovery, koneksi, heartbeat, reset hasil, penyimpanan error, dan bridging ke channel Android.
- Hal yang wajib Anda sesuaikan:
  1. Import path relatif apabila Anda memindahkan service ke folder berbeda.
  2. Konstanta channel (`_scanChannel`, `_scanEvents`, `_adapterStateEvents`) jika Anda mengganti nama channel pada MainActivity.
  3. Pesan teks (`_lastError`) bila ingin bahasa/istilah berbeda.
- Inisialisasi di `main()` menggunakan state management (mis. `ChangeNotifierProvider`).
- Pastikan `dispose()` service dipanggil otomatis oleh Provider ketika aplikasi ditutup.

### b. UI & Logika Presentasi
- File utama saat ini: `lib/main.dart`.
- Komponen penting yang perlu ikut (boleh dipisah menjadi beberapa file):
  - **Halaman Utama:** `PrinterHomePage`, `_ConnectionOverview`, `_TestPrintCard`, `_ErrorCard`.
  - **Halaman Discovery:** `BluetoothDiscoveryPage`, `_ScanHeader`, `_DiscoveredSection`, `_DeviceTile`, `_DiscoveryPlaceholder`, `_BluetoothOffBanner`, `_StatusChip`, `_NewBadge`.
- Pastikan Anda menyalin helper seperti `_showSnack` jika diperlukan.
- Sesuaikan teks UI, ikon, dan style agar mengikuti brand proyek baru.
- Jika aplikasi Anda menggunakan Navigator berbeda (mis. `GoRouter`), ganti `Navigator.of(context).push` sesuai kebutuhan.

### c. Integrasi Provider
- Bungkus root app dengan `ChangeNotifierProvider(create: (_) => BluetoothPrinterManager())` atau adapter state management pilihan Anda.
- Contoh `main()` minimal:
  ```dart
  void main() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      ChangeNotifierProvider(
        create: (_) => BluetoothPrinterManager(),
        child: const MyApp(),
      ),
    );
  }
  ```
- Pastikan halaman memanggil `context.watch<BluetoothPrinterManager>()` untuk rebuild otomatis.
- Jika memakai Riverpod/BLoC, sediakan adaptor yang memanggil API service yang sama.

---

## 3. Android Native Layer

### a. MainActivity
- File sumber: `android/app/src/main/kotlin/com/example/test_print_thermal/MainActivity.kt`.
- Langkah migrasi:
  1. Salin file ke path baru (`android/app/src/main/kotlin/<package_baru>/MainActivity.kt`).
  2. Ubah baris `package com.example.test_print_thermal` menjadi package Anda sendiri.
  3. Jika modul sudah punya MainActivity, gabungkan logika channel ke kelas tersebut alih-alih membuat kelas baru.
- Komponen penting di file ini:
  - **MethodChannel** `"com.example.test_print_thermal/bluetooth_scan"` untuk `startDiscovery`, `stopDiscovery`, `getDiscoveredDevices`, `getAdapterState`.
  - **EventChannel** `"com.example.test_print_thermal/bluetooth_scan_events"` & `".../bluetooth_adapter_state"` untuk streaming hasil discovery + status adapter.
  - **BroadcastReceiver** untuk `BluetoothDevice.ACTION_FOUND` dan `BluetoothAdapter.ACTION_STATE_CHANGED`.
  - **Permission handling** (runtime) untuk API 31+ (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`).
- Jangan lupa mengganti nama channel di sisi Dart jika Anda mengubah konstanta string di sini.

### b. Android Manifest & Permission
- File: `android/app/src/main/AndroidManifest.xml`.
- Pastikan permission berikut tersedia dan disesuaikan dengan minSdk Anda:
  ```xml
  <uses-permission android:name="android.permission.BLUETOOTH" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
  <uses-permission
      android:name="android.permission.BLUETOOTH_SCAN"
      android:usesPermissionFlags="neverForLocation"
      tools:targetApi="s" />
  <uses-permission
      android:name="android.permission.BLUETOOTH_CONNECT"
      tools:targetApi="s" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  ```
- Tambahkan `<uses-feature android:name="android.hardware.bluetooth" android:required="false"/>` bila Anda ingin tetap bisa berjalan di perangkat tanpa Bluetooth.
- Jika target API 31+, Google Play mewajibkan deklarasi permission di Play Console; siapkan teks deskripsi pengguna juga.

### c. Gradle Konfigurasi
- `android/app/build.gradle.kts`
  - Atur `namespace`, `applicationId`, `compileSdk`, `targetSdk`, `minSdk`, dan `ndkVersion = "27.0.12077973"` atau versi yang tersedia di mesin Anda.
  - Pastikan `kotlinOptions.jvmTarget = "11"`, `compileOptions` Java 11, serta plugin Kotlin (`id("kotlin-android")`).
  - Jika Anda menambah ProGuard atau signing config, jangan lupa menambahkan aturan untuk menjaga kelas channel tetap ada.
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
- Pastikan `local.properties` menunjuk ke SDK yang benar, contoh:
  ```
  sdk.dir=C:\\Android\\Sdk
  ```
- Jika memakai versi NDK berbeda, ubah `ndkVersion` di `android/app/build.gradle.kts` agar cocok; jalankan `flutter clean` setelah mengganti.

---

## 4. iOS / macOS (Opsional)
- Tidak ada kode native khusus, tetapi plugin tetap memerlukan izin.
- Tambahkan key berikut pada `ios/Runner/Info.plist` jika menargetkan iOS:
  ```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Aplikasi membutuhkan akses Bluetooth untuk menghubungkan printer.</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>Diperlukan untuk menemukan dan terhubung ke printer thermal.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Lokasi diperlukan oleh iOS untuk proses pemindaian perangkat Bluetooth.</string>
  ```
- Jalankan `cd ios && pod install` setelah `flutter pub get` untuk memastikan plugin terpasang.
- Untuk macOS, pastikan `macos/Runner/DebugProfile.entitlements` mengizinkan Bluetooth (tambahkan `com.apple.security.device.bluetooth = true` jika dibutuhkan).

---

## 5. Langkah Migrasi Cepat

1. **Duplikasi konfigurasi**: salin `pubspec.yaml`, jalankan `flutter pub get`, lalu commit awal jika perlu.
2. **Copy service & UI**: letakkan `bluetooth_printer_service.dart` dan widget terkait di struktur `lib/` proyek baru.
3. **Suntikkan provider**: ubah `main.dart` baru agar menginisialisasi `BluetoothPrinterManager`.
4. **Pindahkan kode native**: salin `MainActivity.kt`, ubah package, dan periksa izin.
5. **Perbarui Gradle & manifest**: cek `namespace`, `applicationId`, `ndkVersion`, serta permission.
6. **Siapkan iOS/macOS** (jika perlu): update Info.plist, jalankan `pod install`.
7. **Validasi**: jalankan `flutter clean`, `flutter run`, dan uji fitur (toggle Bluetooth, scan baru, reset hasil, test print).
8. **Monitoring**: perhatikan logcat untuk channel `BluetoothAdapter` guna memastikan event adapter diterima.

Dengan mengikuti checklist di atas, Anda dapat memindahkan seluruh fitur thermal printer (discovery, reset hasil, status Bluetooth, koneksi, dan test print) ke proyek manapun tanpa kehilangan fungsionalitas penting. Gunakan dokumen ini sebagai referensi hidup—perbarui jika Anda menambah fitur (mis. penyimpanan riwayat atau UI baru) agar migrasi berikutnya semakin mudah.
