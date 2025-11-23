import 'dart:async';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BluetoothPrinterManager extends ChangeNotifier {
  BluetoothPrinterManager() {
    _stateSub = _bluetooth.onStateChanged().listen(_handleStateChange);
    _scanSub = _scanEvents.receiveBroadcastStream().listen(
      _handleScanEvent,
      onError: (Object error) {
        _lastError = error.toString();
        notifyListeners();
      },
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _adapterStateSub = _adapterStateEvents.receiveBroadcastStream().listen(
        _handleAdapterStateEvent,
        onError: _handleAdapterStreamError,
      );
    }
    _startConnectionHeartbeat();
    _startAdapterPolling();
    _syncInitialState();
    unawaited(refreshBondedDevices());
  }

  static const MethodChannel _scanChannel = MethodChannel(
    'com.example.test_print_thermal/bluetooth_scan',
  );
  static const EventChannel _scanEvents = EventChannel(
    'com.example.test_print_thermal/bluetooth_scan_events',
  );
  static const EventChannel _adapterStateEvents = EventChannel(
    'com.example.test_print_thermal/bluetooth_adapter_state',
  );

  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
  final List<BluetoothDevice> _devices = [];
  final List<BluetoothDevice> _discoveredDevices = [];
  final Set<String> _freshDiscoveryAddresses = <String>{};
  StreamSubscription<int?>? _stateSub;
  StreamSubscription<dynamic>? _scanSub;
  StreamSubscription<dynamic>? _adapterStateSub;
  Timer? _discoveryDebounce;
  Timer? _discoveryRestartTimer;
  Timer? _adapterPollTimer;
  Timer? _connectionHeartbeat;

  BluetoothDevice? _connectedDevice;
  bool _isBondedLoading = false;
  bool _isDiscovering = false;
  bool _isConnecting = false;
  bool _resetDiscoveredPending = false;
  bool _keepDiscovering = false;
  bool _isBluetoothEnabled = true;
  String? _lastError;

  List<BluetoothDevice> get devices => List.unmodifiable(_devices);
  List<BluetoothDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isBondedLoading;
  bool get isDiscovering => _isDiscovering;
  bool get isConnecting => _isConnecting;
  bool get isBluetoothEnabled => _isBluetoothEnabled;
  String? get lastError => _lastError;
  bool isFreshDiscovery(String? address) =>
      address != null && _freshDiscoveryAddresses.contains(address);

  Future<void> _syncInitialState() async {
    final isConnected = (await _bluetooth.isConnected) ?? false;
    if (!isConnected) return;

    final bonded = await _bluetooth.getBondedDevices();
    _devices
      ..clear()
      ..addAll(bonded);

    if (bonded.isNotEmpty) {
      _connectedDevice = bonded.firstWhere(
        (d) => d.connected == true,
        orElse: () => bonded.first,
      );
    }
    notifyListeners();
  }

  Future<void> refreshBondedDevices() async {
    if (_isBondedLoading) return;
    _isBondedLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final bonded = await _bluetooth.getBondedDevices();
      _devices
        ..clear()
        ..addAll(bonded);
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isBondedLoading = false;
      notifyListeners();
    }
  }

  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    if (!_isBluetoothEnabled) {
      _lastError = 'Bluetooth perangkat nonaktif';
      notifyListeners();
      return;
    }
    _keepDiscovering = true;
    _isDiscovering = true;
    _lastError = null;
    _freshDiscoveryAddresses.clear();
    _resetDiscoveredPending = true;
    notifyListeners();

    await _invokePlatformDiscovery();
  }

  Future<void> stopDiscovery() async {
    _keepDiscovering = false;
    _discoveryRestartTimer?.cancel();
    try {
      await _scanChannel.invokeMethod('stopDiscovery');
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isDiscovering = false;
      _resetDiscoveredPending = false;
      notifyListeners();
    }
  }

  void resetDiscoveryResults() {
    _freshDiscoveryAddresses.clear();
    _discoveredDevices.clear();
    _resetDiscoveredPending = false;
    notifyListeners();
  }

  Future<bool> connect(BluetoothDevice device) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    _lastError = null;
    notifyListeners();

    try {
      await _bluetooth.connect(device);
      _connectedDevice = device;
      return true;
    } catch (e) {
      _lastError = e.toString();
      _connectedDevice = null;
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<bool> disconnect() async {
    try {
      await _bluetooth.disconnect();
      _connectedDevice = null;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> printTestTicket() async {
    if (!await _isDeviceReady()) return false;

    final now = DateTime.now();
    await _bluetooth.printNewLine();
    await _bluetooth.printCustom('TEST PRINT', 3, 1);
    await _bluetooth.printNewLine();
    await _bluetooth.printCustom('Bluetooth Thermal Demo', 1, 1);
    await _bluetooth.printLeftRight('Tanggal', _formatDate(now), 1);
    await _bluetooth.printLeftRight('Status', 'Berhasil', 1);
    await _bluetooth.printCustom('------------------------------', 1, 1);
    await _bluetooth.printCustom('Terima kasih telah mencoba.', 1, 1);
    await _bluetooth.printNewLine();
    await _bluetooth.printNewLine();
    return true;
  }

  Future<bool> _isDeviceReady() async {
    final isConnected = (await _bluetooth.isConnected) ?? false;
    if (!isConnected) {
      _lastError = 'Printer belum terhubung';
      notifyListeners();
    }
    return isConnected;
  }

  void _handleStateChange(int? state) {
    if (state == null) return;
    var notified = false;

    if (state == BlueThermalPrinter.STATE_OFF ||
        state == BlueThermalPrinter.STATE_TURNING_OFF) {
      if (_isBluetoothEnabled) {
        _isBluetoothEnabled = false;
        _handleBluetoothDisabled();
      }
      return;
    }

    if (state == BlueThermalPrinter.STATE_ON ||
        state == BlueThermalPrinter.STATE_TURNING_ON) {
      if (!_isBluetoothEnabled) {
        _isBluetoothEnabled = true;
        _lastError = null;
        notifyListeners();
        notified = true;
      }
    }

    if (state == BlueThermalPrinter.CONNECTED) {
      notified = true;
      notifyListeners();
    } else if (state == BlueThermalPrinter.DISCONNECTED ||
        state == BlueThermalPrinter.DISCONNECT_REQUESTED) {
      _connectedDevice = null;
      notified = true;
      notifyListeners();
    }

    if (!notified) {
      notifyListeners();
    }
  }

  Future<void> _syncDiscoveredSnapshot() async {
    try {
      final raw = await _scanChannel.invokeMethod<List<dynamic>>(
        'getDiscoveredDevices',
      );
      if (raw == null) return;
      for (final dynamic entry in raw) {
        if (entry is Map) {
          _upsertDiscovered(Map<dynamic, dynamic>.from(entry));
        }
      }
      _scheduleDiscoveryUpdate();
    } catch (_) {
      // Ignore snapshot errors; discovery stream will provide updates.
    }
  }

  void _handleScanEvent(dynamic payload) {
    if (payload is! Map) return;
    final map = Map<dynamic, dynamic>.from(payload);
    final type = map['type'];
    if (type == 'device') {
      if (_resetDiscoveredPending) {
        _discoveredDevices.clear();
        _resetDiscoveredPending = false;
      }
      _upsertDiscovered(map);
      _scheduleDiscoveryUpdate();
    } else if (type == 'complete') {
      if (_resetDiscoveredPending) {
        _discoveredDevices.clear();
        _resetDiscoveredPending = false;
      }
      if (_keepDiscovering) {
        _scheduleDiscoveryRestart();
      } else {
        _isDiscovering = false;
        _scheduleDiscoveryUpdate();
      }
    }
  }

  void _upsertDiscovered(Map<dynamic, dynamic> data) {
    final address = data['address'] as String?;
    if (address == null) return;
    final name = data['name'] as String?;
    final candidate = BluetoothDevice(name, address);
    if (_isDiscovering) {
      _freshDiscoveryAddresses.add(address);
    }
    final index = _discoveredDevices.indexWhere(
      (device) => device.address == address,
    );
    if (index >= 0) {
      _discoveredDevices[index] = candidate;
    } else {
      _discoveredDevices.add(candidate);
    }
  }

  void _scheduleDiscoveryUpdate() {
    _discoveryDebounce ??= Timer(const Duration(milliseconds: 120), () {
      _discoveryDebounce = null;
      notifyListeners();
    });
  }

  void _scheduleDiscoveryRestart() {
    _discoveryRestartTimer?.cancel();
    _discoveryRestartTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_keepDiscovering) return;
      unawaited(_invokePlatformDiscovery());
    });
  }

  Future<void> _invokePlatformDiscovery() async {
    try {
      unawaited(
        _scanChannel
            .invokeMethod('startDiscovery')
            .catchError(_handleDiscoveryError),
      );
      await _syncDiscoveredSnapshot();
    } catch (e) {
      _handleDiscoveryError(e);
    }
  }

  void _handleDiscoveryError(Object error) {
    _lastError = error.toString();
    _keepDiscovering = false;
    _isDiscovering = false;
    _resetDiscoveredPending = false;
    _discoveryRestartTimer?.cancel();
    notifyListeners();
  }

  void _handleAdapterStreamError(Object error) {
    if (error is MissingPluginException) {
      _adapterStateSub?.cancel();
      _adapterStateSub = null;
      return;
    }
    _lastError = error.toString();
    notifyListeners();
  }

  void _handleAdapterStateEvent(dynamic data) {
    if (data is! Map) return;
    final state = data['state'] as int?;
    if (state == null) return;
    const stateOff = 10; // BluetoothAdapter.STATE_OFF
    const stateTurningOff = 13; // BluetoothAdapter.STATE_TURNING_OFF
    const stateOn = 12; // BluetoothAdapter.STATE_ON
    const stateTurningOn = 11; // BluetoothAdapter.STATE_TURNING_ON

    if (state == stateOff || state == stateTurningOff) {
      if (_isBluetoothEnabled) {
        _isBluetoothEnabled = false;
        _handleBluetoothDisabled();
      }
    } else if (state == stateOn || state == stateTurningOn) {
      if (!_isBluetoothEnabled) {
        _isBluetoothEnabled = true;
        if (_lastError == 'Bluetooth perangkat dimatikan') {
          _lastError = null;
        }
        notifyListeners();
      }
    }
  }

  void _handleBluetoothDisabled() {
    _connectedDevice = null;
    _keepDiscovering = false;
    _isDiscovering = false;
    _discoveryRestartTimer?.cancel();
    _discoveryDebounce?.cancel();
    _freshDiscoveryAddresses.clear();
    _discoveredDevices.clear();
    _resetDiscoveredPending = false;
    _lastError = 'Bluetooth perangkat dimatikan';
    notifyListeners();
    unawaited(_scanChannel.invokeMethod('stopDiscovery').catchError((_) {}));
    unawaited(_bluetooth.disconnect().catchError((_) {}));
  }

  void _startAdapterPolling() {
    _adapterPollTimer?.cancel();
    unawaited(_queryAdapterState());
    _adapterPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_queryAdapterState()),
    );
  }

  void _startConnectionHeartbeat() {
    _connectionHeartbeat?.cancel();
    _connectionHeartbeat = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_verifyConnectionState()),
    );
  }

  Future<void> _queryAdapterState() async {
    try {
      final state = await _scanChannel.invokeMethod<int>('getAdapterState');
      if (state != null) {
        _handleAdapterStateEvent({'state': state});
      }
    } on MissingPluginException {
      if (_isBluetoothEnabled) {
        _isBluetoothEnabled = false;
        _handleBluetoothDisabled();
      }
    } catch (_) {
      // Ignore polling failures; event channel will update when possible.
    }
  }

  Future<void> _verifyConnectionState() async {
    try {
      final isConnected = (await _bluetooth.isConnected) ?? false;
      if (!isConnected && _connectedDevice != null) {
        _connectedDevice = null;
        notifyListeners();
      }
    } catch (_) {
      // Ignore connection probe failures.
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _scanSub?.cancel();
    _adapterStateSub?.cancel();
    _discoveryDebounce?.cancel();
    _discoveryRestartTimer?.cancel();
    _adapterPollTimer?.cancel();
    _connectionHeartbeat?.cancel();
    unawaited(stopDiscovery());
    super.dispose();
  }
}
