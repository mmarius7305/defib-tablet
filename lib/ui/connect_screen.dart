import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_state.dart';
import '../ble/ble_transport.dart';
import 'monitor_screen.dart';

/// Ecranul de pornire: alegi sursa de date (simulator sau Bluetooth LE)
/// și mergi la monitorul live.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _scanning = false;
  final List<BluetoothDevice> _found = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _found
            ..clear()
            ..addAll(results.map((r) => r.device));
        });
      }
    });
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  @override
  Widget build(BuildContext context) {
    final appState = InheritedAppState.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('DefibTablet — Conectare')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle, size: 40),
              title: const Text('Simulator integrat'),
              subtitle: const Text(
                  'Rulează fără hardware: ECG și semne vitale sintetice, '
                  'comenzi de ritm și șoc de test.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await appState.connectSimulator();
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MonitorScreen()),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Dispozitiv Bluetooth LE',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      FilledButton(
                        onPressed: _scanning
                            ? null
                            : () async {
                                setState(() => _scanning = true);
                                await _startScan();
                                setState(() => _scanning = false);
                              },
                        child: Text(_scanning ? 'Scanează...' : 'Scanează'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Notă: conectarea reală la Corpuls 3 necesită UUID-urile '
                    'din documentația oficială de parteneriat (vezi README). '
                    'Până atunci, driverul Corpuls rămâne schelet.',
                    style: TextStyle(fontSize: 12),
                  ),
                  ..._found.map((d) => ListTile(
                        title: Text(d.platformName.isNotEmpty
                            ? d.platformName
                            : d.remoteId.str),
                        subtitle: Text(d.remoteId.str),
                        trailing: const Icon(Icons.bluetooth),
                        onTap: () => _onDeviceTap(context, appState, d),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDeviceTap(
      BuildContext context, AppState appState, BluetoothDevice device) async {
    try {
      final transport = BleTransport(
        device: device,
        // TODO(corpuls): înlocuiește cu UUID-urile reale (vezi CorpulsDriver).
        serviceUuid: Guid('0000ffff-0000-0000-0000-000000000000'),
        rxCharacteristicUuid: Guid('0000ff01-0000-0000-0000-000000000000'),
        txCharacteristicUuid: Guid('0000ff02-0000-0000-0000-000000000000'),
      );
      await transport.connect();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              'Transport BLE deschis, dar driverul Corpuls încă nu parsează '
              'date (necesită documentația oficială).')),
        );
      }
      await transport.close();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Conectare BLE eșuată: $e')));
      }
    }
  }
}

/// InheritedWidget simplu prin care ecranele ajung la [AppState].
class InheritedAppState extends InheritedNotifier<AppState> {
  const InheritedAppState({
    super.key,
    required super.notifier,
    required super.child,
  });

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedAppState>()!
          .notifier!;

  @override
  bool updateShouldNotify(InheritedAppState oldWidget) => true;
}
