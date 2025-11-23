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
