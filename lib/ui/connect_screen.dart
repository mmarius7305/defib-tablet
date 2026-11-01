import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_state.dart';
import '../ble/ble_transport.dart';
import 'crew_screen.dart';
import 'monitor_screen.dart';

/// Ecranul de pornire: alegi sursa (simulator, TCP remote, BLE, echipaj).
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _scanning = false;
  bool _connectingTcp = false;
  final List<BluetoothDevice> _found = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final _hostCtrl = TextEditingController(text: '127.0.0.1');
  final _portCtrl = TextEditingController(text: '45678');

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
    _hostCtrl.dispose();
    _portCtrl.dispose();
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
                  const Text('Telecomandă TCP (SAJLink)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'Conectează la sim_server (dart run tool/sim_server.dart) '
                    'sau la un aparat SAJLink din LAN. Host/port configurabile — '
                    'fără IP-uri de producție hardcodate.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Host',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _portCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _connectingTcp
                        ? null
                        : () async {
                            setState(() => _connectingTcp = true);
                            try {
                              await appState.connectTcpRemote(
                                host: _hostCtrl.text.trim(),
                                port: int.parse(_portCtrl.text.trim()),
                              );
                              if (context.mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const MonitorScreen()),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Conectare TCP eșuată: $e')),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _connectingTcp = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.settings_remote),
                    label: Text(_connectingTcp
                        ? 'Conectare...'
                        : 'Conectează telecomandă'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.emergency, size: 40),
              title: const Text('Echipaj — timpi misiune'),
              subtitle: const Text(
                  'Butoane PLECARE / SOSIRE / … / LIBER pe gateway, '
                  'stare ONLINE / STORE-AND-FORWARD, navigare GPS.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CrewScreen()),
                );
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
