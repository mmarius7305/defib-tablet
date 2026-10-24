import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:defib_core/connection.dart';
import 'package:defib_core/models.dart';
import 'package:defib_core/simulator.dart';

/// Starea aplicației: leagă driverul de defibrilator de interfață.
///
/// Acumulăm ECG-ul într-un [EcgWaveform] (30 s la 250 Hz), păstrăm ultima
/// măsurătoare de semne vitale și ultimele evenimente, și notifică UI-ul.
class AppState extends ChangeNotifier {
  DefibrillatorDriver? driver;
  DriverState connState = DriverState.disconnected;
  String statusMessage = 'Deconectat';

  final EcgWaveform ecg = EcgWaveform(sampleRateHz: 250);
  VitalsSample? latestVitals;
  final List<DefibEvent> events = [];
  final List<String> log = [];

  StreamSubscription<double>? _ecgSub;
  StreamSubscription<VitalsSample>? _vitalsSub;
  StreamSubscription<DefibEvent>? _eventsSub;

  /// Notifier separat pentru redesenarea ECG (cu ~30 fps, nu la fiecare mostră).
  final ValueNotifier<int> ecgTick = ValueNotifier(0);
  int _tickAccum = 0;

  void _log(String msg) {
    log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $msg');
    if (log.length > 200) log.removeLast();
  }

  /// Conectează driverul peste un transport dat.
  Future<void> connect({
    required DefibrillatorDriver newDriver,
    required ByteTransport transport,
  }) async {
    await disconnect();
    ecg.clear();
    events.clear();
    latestVitals = null;

    driver = newDriver;
    _ecgSub = newDriver.ecgMillivolts.listen(_onEcgSample);
    _vitalsSub = newDriver.vitals.listen(_onVitals);
    _eventsSub = newDriver.events.listen(_onEvent);

    connState = DriverState.connecting;
    statusMessage = 'Conectare la ${newDriver.name}...';
    notifyListeners();

    try {
      await newDriver.connect(transport);
      connState = newDriver.state;
      statusMessage = 'Conectat: ${newDriver.name}';
      _log('Conectat la ${newDriver.name}.');
    } catch (e) {
      connState = DriverState.error;
      statusMessage = 'Eroare conectare: $e';
      _log('Eroare conectare: $e');
    }
    notifyListeners();
  }

  /// Comoditate: pornește simulatorul integrat.
  Future<void> connectSimulator() async {
    final d = SimulatorDriver();
    await connect(newDriver: d, transport: SimulatorTransport());
  }

  /// Schimbă ritmul simulatorului (activ doar pe simulator).
  Future<void> simulateRhythm(SimRhythm rhythm) async {
    final d = driver;
    if (d is SimulatorDriver) {
      await d.setRhythm(rhythm);
      _log('Ritm simulat: $rhythm');
    }
  }

  /// Administrează un șoc de test (activ doar pe simulator).
  Future<void> simulateShock({int joules = 150}) async {
    final d = driver;
    if (d is SimulatorDriver) {
      await d.deliverShock(joules: joules);
      _log('Șoc simulat: ${joules}J');
    }
  }

  void _onEcgSample(double millivolts) {
    ecg.push(millivolts);
    // Redesenează la maximum ~30 fps.
    _tickAccum++;
    if (_tickAccum >= 8) {
      _tickAccum = 0;
      ecgTick.value++;
    }
  }

  void _onVitals(VitalsSample v) {
    latestVitals = v;
    notifyListeners();
  }

  void _onEvent(DefibEvent e) {
    events.insert(0, e);
    if (events.length > 100) events.removeLast();
    _log('Eveniment: ${e.type.name}'
        '${e.energyJoules != null ? " ${e.energyJoules}J" : ""}');
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _ecgSub?.cancel();
    await _vitalsSub?.cancel();
    await _eventsSub?.cancel();
    _ecgSub = null;
    _vitalsSub = null;
    _eventsSub = null;
    final d = driver;
    driver = null;
    if (d != null) {
      await d.disconnect();
      _log('Deconectat de la ${d.name}.');
    }
    connState = DriverState.disconnected;
    statusMessage = 'Deconectat';
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
