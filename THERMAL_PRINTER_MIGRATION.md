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

Contoh implementasi lengkap saat ini:

```kotlin
package com.example.test_print_thermal

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

  companion object {
    private const val SCAN_CHANNEL = "com.example.test_print_thermal/bluetooth_scan"
    private const val SCAN_EVENTS = "com.example.test_print_thermal/bluetooth_scan_events"
    private const val ADAPTER_STATE_EVENTS = "com.example.test_print_thermal/bluetooth_adapter_state"
    private const val REQUEST_SCAN_PERMISSIONS = 0x4242
  }

  private var scanEventSink: EventChannel.EventSink? = null
  private var discoveryReceiver: BroadcastReceiver? = null
  private var adapterStateReceiver: BroadcastReceiver? = null
  private var adapterStateSink: EventChannel.EventSink? = null
  private val discoveredDevices = LinkedHashMap<String, Map<String, String?>>()
  private var pendingPermissionResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCAN_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "startDiscovery" -> startDiscovery(result)
          "stopDiscovery" -> {
            stopDiscovery()
            result.success(true)
          }
          "getDiscoveredDevices" -> result.success(discoveredDevices.values.toList())
          "getAdapterState" -> result.success(bluetoothAdapter()?.state ?: BluetoothAdapter.ERROR)
          else -> result.notImplemented()
        }
      }

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCAN_EVENTS)
      .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          scanEventSink = events
          emitCurrentDevices()
        }

        override fun onCancel(arguments: Any?) {
          scanEventSink = null
        }
      })

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, ADAPTER_STATE_EVENTS)
      .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          adapterStateSink = events
          emitAdapterState()
          registerAdapterStateReceiver()
        }

        override fun onCancel(arguments: Any?) {
          adapterStateSink = null
          unregisterAdapterStateReceiver()
        }
      })
  }

  override fun onDestroy() {
    super.onDestroy()
    stopDiscovery()
    unregisterDiscoveryReceiver()
    unregisterAdapterStateReceiver()
  }

  private fun startDiscovery(result: MethodChannel.Result) {
    val adapter = bluetoothAdapter() ?: run {
      result.error("unavailable", "Bluetooth adapter not available", null)
      return
    }
    if (!adapter.isEnabled) {
      result.error("bluetooth_off", "Bluetooth is disabled", null)
      return
    }

    if (!ensurePermissions(result)) {
      return
    }

    discoveredDevices.clear()
    registerDiscoveryReceiver()
    adapter.cancelDiscovery()
    val started = adapter.startDiscovery()
    result.success(started)
    if (!started) {
      scanEventSink?.error("discovery_failed", "Unable to start discovery", null)
    }
  }

  private fun stopDiscovery() {
    bluetoothAdapter()?.cancelDiscovery()
  }

  private fun registerDiscoveryReceiver() {
    if (discoveryReceiver != null) return

    discoveryReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        when (intent?.action) {
          BluetoothDevice.ACTION_FOUND -> {
            val device: BluetoothDevice? =
              intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
            val address = device?.address ?: return
            val payload = hashMapOf(
              "type" to "device",
              "name" to device.name,
              "address" to address
            )
            if (!discoveredDevices.containsKey(address)) {
              discoveredDevices[address] = payload
            }
            scanEventSink?.success(payload)
          }

          BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
            scanEventSink?.success(hashMapOf("type" to "complete"))
          }
        }
      }
    }

    val filter = IntentFilter().apply {
      addAction(BluetoothDevice.ACTION_FOUND)
      addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
    }
    registerReceiver(discoveryReceiver, filter)
  }

  private fun registerAdapterStateReceiver() {
    if (adapterStateReceiver != null) return

    adapterStateReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
          val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
          adapterStateSink?.success(hashMapOf("state" to state))
          if (state == BluetoothAdapter.STATE_TURNING_OFF || state == BluetoothAdapter.STATE_OFF) {
            stopDiscovery()
            discoveredDevices.clear()
          }
        }
      }
    }

    val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
    registerReceiver(adapterStateReceiver, filter)
  }

  private fun unregisterAdapterStateReceiver() {
    adapterStateReceiver?.let { receiver ->
      try {
        unregisterReceiver(receiver)
      } catch (_: IllegalArgumentException) {
      }
    }
    adapterStateReceiver = null
  }

  private fun unregisterDiscoveryReceiver() {
    discoveryReceiver?.let { receiver ->
      try {
        unregisterReceiver(receiver)
      } catch (_: IllegalArgumentException) {
      }
    }
    discoveryReceiver = null
  }

  private fun ensurePermissions(result: MethodChannel.Result): Boolean {
    val needed = mutableListOf<String>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val permissions = arrayOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.ACCESS_FINE_LOCATION
      )
      permissions.forEach { perm ->
        if (ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED) {
          needed.add(perm)
        }
      }
    } else {
      val permissions = arrayOf(
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.ACCESS_FINE_LOCATION
      )
      permissions.forEach { perm ->
        if (ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED) {
          needed.add(perm)
        }
      }
    }

    if (needed.isNotEmpty()) {
      pendingPermissionResult = result
      ActivityCompat.requestPermissions(this, needed.toTypedArray(), REQUEST_SCAN_PERMISSIONS)
      return false
    }
    return true
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == REQUEST_SCAN_PERMISSIONS) {
      val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
      pendingPermissionResult?.let { pending ->
        if (granted) {
          startDiscovery(pending)
        } else {
          pending.error("no_permissions", "Bluetooth scan permissions denied", null)
        }
      }
      pendingPermissionResult = null
    }
  }

  private fun emitCurrentDevices() {
    discoveredDevices.values.forEach { device ->
      scanEventSink?.success(device)
    }
  }

  private fun emitAdapterState() {
    val state = bluetoothAdapter()?.state ?: BluetoothAdapter.ERROR
    adapterStateSink?.success(hashMapOf("state" to state))
  }

  private fun bluetoothAdapter(): BluetoothAdapter? {
    val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    return manager?.adapter
  }
}
```

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

    Cuplikan file `android/app/build.gradle.kts` saat ini:

    ```kotlin
    plugins {
      id("com.android.application")
      id("kotlin-android")
      // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
      id("dev.flutter.flutter-gradle-plugin")
    }

    android {
      namespace = "com.example.test_print_thermal"
      compileSdk = flutter.compileSdkVersion
      ndkVersion = "27.0.12077973"

      compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
      }

      kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
      }

      defaultConfig {
        applicationId = "com.example.test_print_thermal"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
      }

      buildTypes {
        release {
          signingConfig = signingConfigs.getByName("debug")
        }
      }
    }

    flutter {
      source = "../.."
    }
    ```

    Dan isi `android/build.gradle.kts` root:

    ```kotlin
    import com.android.build.gradle.LibraryExtension

    allprojects {
      repositories {
        google()
        mavenCentral()
      }
    }

    val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
    rootProject.layout.buildDirectory.value(newBuildDir)

    subprojects {
      val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
      project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
    subprojects {
      project.evaluationDependsOn(":app")
    }

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

    tasks.register<Delete>("clean") {
      delete(rootProject.layout.buildDirectory)
    }
    ```

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
