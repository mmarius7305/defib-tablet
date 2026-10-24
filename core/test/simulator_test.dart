import 'dart:async';

import 'package:test/test.dart';

import 'package:defib_core/simulator.dart';

/// Numără vârfurile QRS dintr-o fereastră ECG (prag + perioadă refractară).
int countQrsPeaks(List<double> samples, int sampleRateHz) {
  const threshold = 0.8; // mV — doar complexul R trece de prag.
  final refractory = (sampleRateHz * 0.3).round(); // max ~200 bpm
  var peaks = 0;
  var lastPeak = -refractory;
  for (var i = 1; i < samples.length; i++) {
    if (samples[i] >= threshold &&
        samples[i] > samples[i - 1] &&
        i - lastPeak >= refractory) {
      peaks++;
      lastPeak = i;
    }
  }
  return peaks;
}

void main() {
  test('ECG sinus la 72 bpm produce ~12 bătăi în 10 secunde', () async {
    final transport = SimulatorTransport()..rhythm = SimRhythm.sinus;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final samples = <double>[];
    final sub = driver.ecgMillivolts.listen(samples.add);
    await Future<void>.delayed(const Duration(seconds: 10));
    await sub.cancel();
    await driver.disconnect();

    expect(samples.length, closeTo(2500, 60)); // 250 Hz * 10 s
    final beats = countQrsPeaks(samples, 250);
    expect(beats, inInclusiveRange(10, 14)); // 72 bpm => 12 bătăți
  });

  test('VT: ritm rapid, complexe late peste 1.5 mV', () async {
    final transport = SimulatorTransport()..rhythm = SimRhythm.vtach;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final samples = <double>[];
    final sub = driver.ecgMillivolts.listen(samples.add);
    await Future<void>.delayed(const Duration(seconds: 6));
    await sub.cancel();
    await driver.disconnect();

    final beats = countQrsPeaks(samples, 250);
    expect(beats, greaterThan(14)); // 180 bpm => ~18 bătăți în 6 s
  });

  test('semnele vitale sunt plauzibile pentru sinus', () async {
    final transport = SimulatorTransport()..rhythm = SimRhythm.sinus;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final vitals = <double>[];
    final sub = driver.vitals.listen((v) => vitals.add(v.heartRate ?? -1));
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    await driver.disconnect();

    expect(vitals, isNotEmpty);
    for (final hr in vitals) {
      expect(hr, inInclusiveRange(60, 90));
    }
  });

  test('comanda de șoc produce eveniment shockDelivered cu energia cerută',
      () async {
    final transport = SimulatorTransport()..rhythm = SimRhythm.vfib;
    final driver = SimulatorDriver();
    await driver.connect(transport);

    final events = <dynamic>[];
    final sub = driver.events.listen(events.add);
    await driver.deliverShock(joules: 200);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    await driver.disconnect();

    expect(events, isNotEmpty);
    final shock = events.last;
    expect(shock.type.toString(), contains('shockDelivered'));
    expect(shock.energyJoules, 200);
  });

  test('schimbarea ritmului emite eveniment rhythmAnalysis', () async {
    final transport = SimulatorTransport()..rhythm = SimRhythm.sinus;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final events = <dynamic>[];
    final sub = driver.events.listen(events.add);
    await driver.setRhythm(SimRhythm.asystole);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    await driver.disconnect();

    expect(events, isNotEmpty);
    expect(events.last.type.toString(), contains('rhythmAnalysis'));
  });
}
