import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/bluetooth_printer_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => BluetoothPrinterManager(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thermal Printer Tester',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const PrinterHomePage(),
    );
  }
}

class PrinterHomePage extends StatelessWidget {
  const PrinterHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<BluetoothPrinterManager>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thermal Printer Tester'),
        actions: [
          IconButton(
            tooltip: 'Scan & Hubungkan',
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BluetoothDiscoveryPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ConnectionOverview(manager: manager),
          const SizedBox(height: 20),
          _TestPrintCard(manager: manager),
          if (manager.lastError != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(message: manager.lastError!),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.settings_bluetooth),
        label: const Text('Kelola Printer'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BluetoothDiscoveryPage()),
        ),
      ),
    );
  }
}

class _ConnectionOverview extends StatelessWidget {
  const _ConnectionOverview({required this.manager});

  final BluetoothPrinterManager manager;

  @override
  Widget build(BuildContext context) {
    final device = manager.connectedDevice;
    final bluetoothOn = manager.isBluetoothEnabled;
    final hasDevice = bluetoothOn && device != null;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: bluetoothOn
                        ? (hasDevice
                              ? Colors.teal.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.1))
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    bluetoothOn
                        ? (hasDevice
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled)
                        : Icons.bluetooth_disabled,
                    color: bluetoothOn
                        ? (hasDevice ? Colors.teal : Colors.red)
                        : Colors.orange,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !bluetoothOn
                            ? 'Bluetooth Nonaktif'
                            : (hasDevice
                                  ? 'Printer Terhubung'
                                  : 'Belum Terhubung'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        !bluetoothOn
                            ? 'Aktifkan Bluetooth perangkat untuk melanjutkan'
                            : (device != null
                                  ? (device.name ?? 'Tanpa Nama')
                                  : 'Hubungkan printer bluetooth terlebih dahulu'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alamat'),
                    Text(
                      bluetoothOn ? (device?.address ?? '-') : '-',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Status'),
                    Text(
                      !bluetoothOn
                          ? 'Mati'
                          : (device != null ? 'Siap' : 'Offline'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TestPrintCard extends StatelessWidget {
  const _TestPrintCard({required this.manager});

  final BluetoothPrinterManager manager;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cetak Contoh Struk',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Gunakan tombol di bawah untuk mencetak bukti sederhana sebagai pengujian koneksi printer thermal.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.print_rounded),
              label: const Text('Cetak Sekarang'),
              onPressed: manager.connectedDevice == null
                  ? null
                  : () async {
                      final success = await manager.printTestTicket();
                      if (!context.mounted) return;
                      _showSnack(
                        context,
                        success
                            ? 'Print test terkirim'
                            : (manager.lastError ?? 'Gagal mencetak'),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BluetoothDiscoveryPage extends StatefulWidget {
  const BluetoothDiscoveryPage({super.key});

  @override
  State<BluetoothDiscoveryPage> createState() => _BluetoothDiscoveryPageState();
}

class _BluetoothDiscoveryPageState extends State<BluetoothDiscoveryPage> {
  late final BluetoothPrinterManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = context.read<BluetoothPrinterManager>();
    Future.microtask(() {
      if (!mounted) return;
      _manager.refreshBondedDevices();
    });
  }

  @override
  void dispose() {
    _manager.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<BluetoothPrinterManager>();

    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Printer')),
      body: RefreshIndicator(
        onRefresh: manager.refreshBondedDevices,
        child: ListView(
          padding: const EdgeInsets.all(24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!manager.isBluetoothEnabled) ...[
              const _BluetoothOffBanner(),
              const SizedBox(height: 16),
            ],
            _ScanHeader(
              isRefreshing: manager.isScanning,
              isDiscovering: manager.isDiscovering,
              isBluetoothEnabled: manager.isBluetoothEnabled,
              hasResults: manager.discoveredDevices.isNotEmpty,
              onToggleDiscovery: () {
                if (manager.isDiscovering) {
                  return manager.stopDiscovery();
                }
                return manager.startDiscovery();
              },
              onResetResults: manager.resetDiscoveryResults,
            ),
            const SizedBox(height: 24),
            _DiscoveredSection(
              manager: manager,
              bluetoothEnabled: manager.isBluetoothEnabled,
            ),
            const SizedBox(height: 24),
            Text(
              'Perangkat Terpasang',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (manager.devices.isEmpty)
              manager.isScanning
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : const _EmptyDevices()
            else
              ...manager.devices.map(
                (device) => _DeviceTile(
                  device: device,
                  isActive: manager.connectedDevice?.address == device.address,
                  isBusy: manager.isConnecting,
                  bluetoothEnabled: manager.isBluetoothEnabled,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: manager.connectedDevice != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.link_off),
              label: const Text('Putuskan'),
              onPressed: manager.isConnecting
                  ? null
                  : () async {
                      final success = await manager.disconnect();
                      if (!context.mounted) return;
                      _showSnack(
                        context,
                        success
                            ? 'Printer diputuskan'
                            : (manager.lastError ?? 'Gagal memutus koneksi'),
                      );
                    },
            )
          : null,
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({
    required this.isRefreshing,
    required this.isDiscovering,
    required this.isBluetoothEnabled,
    required this.hasResults,
    required this.onToggleDiscovery,
    required this.onResetResults,
  });

  final bool isRefreshing;
  final bool isDiscovering;
  final bool isBluetoothEnabled;
  final bool hasResults;
  final Future<void> Function() onToggleDiscovery;
  final VoidCallback onResetResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bluetooth_searching, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isRefreshing
                    ? 'Memperbarui daftar perangkat terpasang...'
                    : 'Tarik ke bawah untuk memuat ulang daftar printer yang sudah dipasangkan.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: isBluetoothEnabled
                  ? () {
                      onToggleDiscovery();
                    }
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    !isBluetoothEnabled
                        ? Icons.bluetooth_disabled
                        : (isDiscovering ? Icons.stop_circle : Icons.radar),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    !isBluetoothEnabled
                        ? 'Aktifkan Bluetooth'
                        : (isDiscovering ? 'Stop Scan' : 'Scan Baru'),
                  ),
                  if (isDiscovering && isBluetoothEnabled) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
            if (hasResults)
              TextButton.icon(
                onPressed: onResetResults,
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('Reset hasil'),
              ),
          ],
        ),
        if (isRefreshing || isDiscovering) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isRefreshing)
                const _StatusChip(
                  icon: Icons.refresh,
                  label: 'Memuat perangkat terpasang',
                ),
              if (isDiscovering)
                const _StatusChip(
                  icon: Icons.radar,
                  label: 'Sedang mencari perangkat',
                ),
            ],
          ),
        ],
        if (!isBluetoothEnabled) ...[
          const SizedBox(height: 12),
          Text(
            'Bluetooth perangkat sedang mati. Aktifkan kembali untuk melakukan scanning atau menghubungkan printer.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _DiscoveredSection extends StatelessWidget {
  const _DiscoveredSection({
    required this.manager,
    required this.bluetoothEnabled,
  });

  final BluetoothPrinterManager manager;
  final bool bluetoothEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairedAddresses = manager.devices
        .map((device) => device.address)
        .whereType<String>()
        .toSet();
    final discovered = manager.discoveredDevices
        .where(
          (device) =>
              device.address != null &&
              !pairedAddresses.contains(device.address),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Hasil Pencarian', style: theme.textTheme.titleMedium),
            if (manager.isDiscovering && bluetoothEnabled) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (!bluetoothEnabled)
          const _DiscoveryPlaceholder(
            isDiscovering: false,
            message:
                'Bluetooth dimatikan. Aktifkan kembali untuk menampilkan perangkat terdekat.',
          )
        else if (discovered.isEmpty)
          _DiscoveryPlaceholder(isDiscovering: manager.isDiscovering)
        else
          ...discovered.map(
            (device) => _DeviceTile(
              device: device,
              isActive: manager.connectedDevice?.address == device.address,
              isBusy: manager.isConnecting,
              showNewBadge: manager.isFreshDiscovery(device.address),
              bluetoothEnabled: bluetoothEnabled,
            ),
          ),
      ],
    );
  }
}

class _DiscoveryPlaceholder extends StatelessWidget {
  const _DiscoveryPlaceholder({required this.isDiscovering, this.message});

  final bool isDiscovering;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text =
        message ??
        (isDiscovering
            ? 'Sedang mencari printer terdekat...'
            : 'Tekan "Scan Baru" untuk memulai pencarian perangkat di sekitar.');
    final icon = message != null
        ? Icons.info_outline
        : (isDiscovering ? Icons.radar : Icons.travel_explore);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _BluetoothOffBanner extends StatelessWidget {
  const _BluetoothOffBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.orange.withValues(alpha: 0.15),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth_disabled, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bluetooth perangkat sedang dimatikan. Aktifkan kembali untuk melanjutkan proses scan atau koneksi printer.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Baru',
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.orange.shade800,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.devices_other,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada printer yang terpasang. Pastikan printer sudah dipasangkan melalui pengaturan Bluetooth perangkat.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isActive,
    required this.isBusy,
    this.showNewBadge = false,
    this.bluetoothEnabled = true,
  });

  final BluetoothDevice device;
  final bool isActive;
  final bool isBusy;
  final bool showNewBadge;
  final bool bluetoothEnabled;

  @override
  Widget build(BuildContext context) {
    final manager = context.read<BluetoothPrinterManager>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive
              ? Colors.teal.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.15),
          child: Icon(
            isActive ? Icons.print : Icons.print_disabled,
            color: isActive ? Colors.teal : Colors.grey,
          ),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(device.name ?? 'Tanpa Nama')),
            if (showNewBadge) ...[const SizedBox(width: 8), const _NewBadge()],
          ],
        ),
        subtitle: Text(device.address ?? '-'),
        trailing: FilledButton(
          onPressed: (!bluetoothEnabled || isActive || isBusy)
              ? null
              : () async {
                  final success = await manager.connect(device);
                  if (!context.mounted) return;
                  _showSnack(
                    context,
                    success
                        ? 'Terhubung ke ${device.name ?? device.address}'
                        : (manager.lastError ?? 'Gagal menghubungkan'),
                  );
                },
          child: isActive
              ? const Text('Terhubung')
              : Text(bluetoothEnabled ? 'Hubungkan' : 'Bluetooth Mati'),
        ),
      ),
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
