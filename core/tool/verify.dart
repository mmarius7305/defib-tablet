
import 'dart:async';
import 'dart:math' as math;

import 'package:defib_core/frames.dart';
import 'package:defib_core/models.dart';
import 'package:defib_core/simulator.dart';

int passed = 0;
int failed = 0;

void check(String name, bool cond, [String? extra]) {
  if (cond) {
    passed++;
    print('  OK   $name');
  } else {
    failed++;
    print('  FAIL $name${extra != null ? " -> $extra" : ""}');
  }
}

/// Numără vârfurile QRS (prag + perioadă refractară).
int countQrsPeaks(List<double> samples, int sampleRateHz) {
  const threshold = 0.8;
  final refractory = (sampleRateHz * 0.3).round();
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

Future<void> main() async {
  print('== frames ==');
  // roundtrip
  {
    final payload = List<int>.generate(37, (i) => (i * 7) & 0xFF);
    final codec = SajLinkCodec()..feed(SajLinkCodec.encode(SajFrame(SajFrameType.vitals, payload)));
    final decoded = codec.decodeNext();
    check('roundtrip decode', decoded != null && decoded.type == SajFrameType.vitals && decoded.payload.length == 37);
  }
  // octet cu octet
  {
    final f1 = SajFrame(SajFrameType.ecgBatch, [1, 2, 3, 4, 5]);
    final f2 = SajFrame(SajFrameType.event, [9, 9]);
    final bytes = [...SajLinkCodec.encode(f1), ...SajLinkCodec.encode(f2)];
    final codec = SajLinkCodec();
    final decoded = <SajFrame>[];
    for (final b in bytes) {
      codec.feed([b]);
      while (true) {
        final f = codec.decodeNext();
        if (f == null) break;
        decoded.add(f);
      }
    }
    check('octet cu octet decodifică 2 cadre', decoded.length == 2 && decoded[0].type == SajFrameType.ecgBatch && decoded[1].type == SajFrameType.event);
  }
  // CRC corupt
  {
    final good = SajFrame(SajFrameType.command, [1, 2, 3]);
    final raw = SajLinkCodec.encode(good).toList();
    raw[8] ^= 0xFF;
    final good2 = SajFrame(SajFrameType.ack, [77]);
    final codec = SajLinkCodec()
      ..feed(raw)
      ..feed(SajLinkCodec.encode(good2));
    final recovered = codec.decodeNext();
    check('CRC corupt respins, următorul valid decodificat',
        recovered != null && recovered.type == SajFrameType.ack && recovered.payload[0] == 77);
    check('bufferul e gol după decodificare', codec.decodeNext() == null);
  }
  // zgomot înainte de magic
  {
    final frame = SajFrame(SajFrameType.error, [0xAA]);
    final codec = SajLinkCodec()
      ..feed([0x00, 0x12, 0x34, 0x53])
      ..feed(SajLinkCodec.encode(frame));
    final decoded = codec.decodeNext();
    check('zgomotul este ignorat', decoded != null && decoded.payload.length == 1 && decoded.payload[0] == 0xAA);
  }
  // payload mare
  {
    final rnd = math.Random(3);
    final payload = List<int>.generate(500, (_) => rnd.nextInt(256));
    final codec = SajLinkCodec()..feed(SajLinkCodec.encode(SajFrame(2, payload)));
    final d = codec.decodeNext();
    check('payload 500 octeți', d != null && d.payload.length == 500);
  }

  print('== EcgWaveform ==');
  {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 8);
    w.pushAll([1, 2, 3]);
    final l = w.lastN(10);
    check('ordine cronologică', l.length == 3 && l[0] == 1 && l[2] == 3 && w.length == 3);
  }
  {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 4);
    w.pushAll([1, 2, 3, 4, 5, 6]);
    final l = w.lastN(4);
    check('suprascriere circulară', w.length == 4 && l.length == 4 && l[0] == 3 && l[3] == 6);
  }
  {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 100);
    w.pushAll([1, 2]);
    check('lastN peste lungime', w.lastN(50).length == 2);
  }
  {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 3);
    w.pushAll([10, 20, 30, 40, 50]);
    check('at(i) după rotiri', w.at(0) == 30 && w.at(1) == 40 && w.at(2) == 50);
  }
  {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 10);
    w.pushAll([1, 2, 3]);
    w.clear();
    check('clear', w.length == 0 && w.lastN(10).isEmpty);
  }

  print('== Simulator ==');
  // sinus 10 s
  {
    final transport = SimulatorTransport()..rhythm = SimRhythm.sinus;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final samples = <double>[];
    final sub = driver.ecgMillivolts.listen(samples.add);
    await Future<void>.delayed(const Duration(seconds: 10));
    await sub.cancel();
    await driver.disconnect();
    final beats = countQrsPeaks(samples, 250);
    check('sinus: ~2500 mostre în 10 s', (samples.length - 2500).abs() <= 60, 'primit ${samples.length}');
    check('sinus: 10-14 bătăi detectate (72 bpm)', beats >= 10 && beats <= 14, 'detectate $beats');
  }
  // VT 6 s
  {
    final transport = SimulatorTransport()..rhythm = SimRhythm.vtach;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final samples = <double>[];
    final sub = driver.ecgMillivolts.listen(samples.add);
    await Future<void>.delayed(const Duration(seconds: 6));
    await sub.cancel();
    await driver.disconnect();
    final beats = countQrsPeaks(samples, 250);
    check('VT: ritm rapid (>14 bătăi în 6 s)', beats > 14, 'detectate $beats');
  }
  // vitals sinus
  {
    final transport = SimulatorTransport()..rhythm = SimRhythm.sinus;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final hrs = <double>[];
    final sub = driver.vitals.listen((v) => hrs.add(v.heartRate ?? -1));
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    await driver.disconnect();
    final ok = hrs.isNotEmpty && hrs.every((h) => h >= 60 && h <= 90);
    check('vitals: HR plauzibil 60-90', ok, 'primit $hrs');
  }
  // șoc
  {
    final transport = SimulatorTransport()..rhythm = SimRhythm.vfib;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final events = <DefibEvent>[];
    final sub = driver.events.listen(events.add);
    await driver.deliverShock(joules: 200);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    await driver.disconnect();
    check('șoc: eveniment shockDelivered cu 200 J',
        events.isNotEmpty && events.last.type == DefibEventType.shockDelivered && events.last.energyJoules == 200);
  }
  // schimbare ritm
  {
    final transport = SimulatorTransport()..rhythm = SimRhythm.sinus;
    final driver = SimulatorDriver();
    await driver.connect(transport);
    final events = <DefibEvent>[];
    final sub = driver.events.listen(events.add);
    await driver.setRhythm(SimRhythm.asystole);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    await driver.disconnect();
    check('schimbare ritm: eveniment rhythmAnalysis',
        events.isNotEmpty && events.last.type == DefibEventType.rhythmAnalysis);
  }

  print('');
  print('REZULTAT: $passed trecute, $failed căzute');
  if (failed > 0) {
    throw StateError('$failed verificări au căzut');
  }
}
