/// Simulator de monitor-defibrilator, pentru dezvoltare și demonstrații.
///
/// Funcționează complet în proces: [SimulatorTransport] joacă rolul aparatului
/// (generează cadre SAJLink cu ECG sintetic și semne vitale), iar
/// [SimulatorDriver] joacă rolul driverului care le decodează. Astfel
/// aplicația rulează integral pe tabletă fără niciun hardware.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'connection.dart';
import 'frames.dart';
import 'models.dart';

/// Ritmurile suportate de simulator.
enum SimRhythm { sinus, vtach, vfib, asystole }

/// Construire simplă de payload-uri binare little-endian.
class Bin {
  final BytesBuilder _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) {
    _b.addByte(v & 0xFF);
    _b.addByte((v >> 8) & 0xFF);
  }
  void i64(int v) {
    for (var i = 0; i < 8; i++) {
      _b.addByte((v >> (8 * i)) & 0xFF);
    }
  }

  void f32(double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    _b.add(bd.buffer.asUint8List());
  }

  Uint8List take() => _b.toBytes();
}

/// Citire simplă de payload-uri binare little-endian.
class BinReader {
  final Uint8List data;
  int pos = 0;
  BinReader(this.data);

  int u8() => data[pos++] & 0xFF;
  int u16() => (data[pos++] & 0xFF) | ((data[pos++] & 0xFF) << 8);
  int i64() {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v |= (data[pos++] & 0xFF) << (8 * i);
    }
    return v;
  }

  double f32() {
    final bd = ByteData.sublistView(data, pos, pos + 4);
    pos += 4;
    return bd.getFloat32(0, Endian.little);
  }
}

/// „Partea de aparat": generează date și le trimite pe transport.
class SimulatorTransport implements ByteTransport {
  final _incoming = StreamController<List<int>>.broadcast();
  final _codec = SajLinkCodec();
  final math.Random _rnd = math.Random(7);
  Timer? _ecgTimer;
  Timer? _vitalsTimer;
  bool _open = false;

  SimRhythm rhythm = SimRhythm.sinus;
  int _ecgPhase = 0; // mostre de la începutul bătăii curente

  static const int sampleRateHz = 250;

  /// Durata unei bătăți, în mostre, pentru ritmul curent.
  int _beatSamples() {
    switch (rhythm) {
      case SimRhythm.sinus:
        return (sampleRateHz * 60 / 72).round(); // ~208
      case SimRhythm.vtach:
        return (sampleRateHz * 60 / 180).round(); // ~83
      case SimRhythm.vfib:
        return (sampleRateHz * 60 / 300).round(); // ~50
      case SimRhythm.asystole:
        return sampleRateHz;
    }
  }

  double _ecgSample(int phaseInBeat) {
    switch (rhythm) {
      case SimRhythm.sinus:
        return _syntheticSinus(phaseInBeat);
      case SimRhythm.vtach:
        final n = _beatSamples();
        final t = phaseInBeat / n;
        if (t < 0.08) return -1.2 * math.sin(t / 0.08 * math.pi);
        if (t < 0.25) return 1.6 * math.sin((t - 0.08) / 0.17 * math.pi);
        if (t < 0.45) return 0.35 * math.sin((t - 0.25) / 0.2 * math.pi);
        return 0.02 * math.sin(phaseInBeat * 0.5);
      case SimRhythm.vfib:
        // Haos sinusal cu frecvențe incomensurabile.
        return 0.55 * math.sin(phaseInBeat * 0.31) +
            0.30 * math.sin(phaseInBeat * 0.113 + 1.7) +
            0.15 * math.sin(phaseInBeat * 0.071 + 0.4);
      case SimRhythm.asystole:
        return 0.02 * math.sin(phaseInBeat * 0.05) + _rnd.nextDouble() * 0.01;
    }
  }

  double _syntheticSinus(int p) {
    final n = _beatSamples();
    final t = p / n; // 0..1 în bătaie
    var v = 0.01 * math.sin(p * 0.3); // linie de bază ușor ondulată
    v += 0.15 * _gauss(t, 0.15, 0.03); // undă P
    v -= 0.10 * _gauss(t, 0.225, 0.008); // Q
    v += 1.10 * _gauss(t, 0.245, 0.010); // R
    v -= 0.25 * _gauss(t, 0.265, 0.012); // S
    v += 0.25 * _gauss(t, 0.45, 0.05); // undă T
    if (_rnd.nextDouble() < 0.001) v += 0.3 * _rnd.nextDouble(); // artefact rar
    return v;
  }

  static double _gauss(double x, double center, double sigma) =>
      math.exp(-((x - center) * (x - center)) / (2 * sigma * sigma));

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  /// Pornește „aparatul" (la conectare).
  void start() {
    _open = true;
    _ecgTimer?.cancel();
    _vitalsTimer?.cancel();
    // Un „tic" = 40 ms = 10 mostre ECG la 250 Hz.
    _ecgTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final b = Bin();
      for (var i = 0; i < 10; i++) {
        b.f32(_ecgSample(_ecgPhase));
        _ecgPhase++;
        if (_ecgPhase >= _beatSamples()) _ecgPhase = 0;
      }
      _incoming.add(SajLinkCodec.encode(SajFrame(SajFrameType.ecgBatch, b.take())));
    });
    _vitalsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sendVitals());
  }

  void _sendVitals() {
    final hr = switch (rhythm) {
      SimRhythm.sinus => 72.0 + _rnd.nextDouble() * 6 - 3,
      SimRhythm.vtach => 180.0 + _rnd.nextDouble() * 10 - 5,
      SimRhythm.vfib => null, // nedefinit în VF
      SimRhythm.asystole => 0.0,
    };
    final double? spo2 = switch (rhythm) {
      SimRhythm.sinus => 96 + _rnd.nextDouble() * 3,
      SimRhythm.vtach => 82 + _rnd.nextDouble() * 6,
      SimRhythm.vfib => 70 + _rnd.nextDouble() * 8,
      SimRhythm.asystole => null,
    };
    final etco2 = switch (rhythm) {
      SimRhythm.sinus => 36.0 + _rnd.nextDouble() * 4 - 2,
      SimRhythm.vtach => 22.0 + _rnd.nextDouble() * 4 - 2,
      SimRhythm.vfib => 14.0,
      SimRhythm.asystole => 4.0,
    };
    final b = Bin()
      ..i64(DateTime.now().millisecondsSinceEpoch)
      ..f32(hr ?? -1)
      ..f32(spo2 ?? -1)
      ..f32(etco2);
    _incoming.add(SajLinkCodec.encode(SajFrame(SajFrameType.vitals, b.take())));
  }

  @override
  Future<void> send(List<int> data) async {
    // Comenzi primite de la aplicație (tot cadre SAJLink).
    _codec.feed(data);
    while (true) {
      final f = _codec.decodeNext();
      if (f == null) break;
      if (f.type == SajFrameType.command) _handleCommand(f.payload);
    }
  }

  void _handleCommand(Uint8List payload) {
    if (payload.isEmpty) return;
    switch (payload[0]) {
      case 1: // schimbă ritmul
        if (payload.length >= 2) {
          final idx = payload[1];
          if (idx >= 0 && idx < SimRhythm.values.length) {
            rhythm = SimRhythm.values[idx];
            _ecgPhase = 0;
            _emitEvent(DefibEventType.rhythmAnalysis, detail: 'Ritm schimbat: $rhythm');
          }
        }
      case 2: // administrează șoc
        final energy =
            payload.length >= 3 ? payload[1] | (payload[2] << 8) : 150;
        _emitEvent(DefibEventType.shockDelivered, energyJoules: energy);
      case 3: // auto-test
        _emitEvent(DefibEventType.deviceSelfTest);
    }
  }

  void _emitEvent(DefibEventType type, {int? energyJoules, String? detail}) {
    final b = Bin()
      ..i64(DateTime.now().millisecondsSinceEpoch)
      ..u8(type.index)
      ..u16(energyJoules ?? 0);
    _incoming.add(SajLinkCodec.encode(SajFrame(SajFrameType.event, b.take())));
  }

  @override
  Future<void> close() async {
    _open = false;
    _ecgTimer?.cancel();
    _vitalsTimer?.cancel();
    _ecgTimer = null;
    _vitalsTimer = null;
  }
}

/// Driverul aplicației pentru simulatorul integrat.
class SimulatorDriver implements DefibrillatorDriver {
  SimulatorTransport? _transport;
  final _codec = SajLinkCodec();

  final _vitals = StreamController<VitalsSample>.broadcast();
  final _ecg = StreamController<double>.broadcast();
  final _events = StreamController<DefibEvent>.broadcast();
  StreamSubscription<List<int>>? _sub;
  DriverState _state = DriverState.disconnected;

  @override
  String get name => 'Simulator SAJLink';

  @override
  DriverState get state => _state;

  @override
  int get ecgSampleRateHz => SimulatorTransport.sampleRateHz;

  @override
  Stream<VitalsSample> get vitals => _vitals.stream;

  @override
  Stream<double> get ecgMillivolts => _ecg.stream;

  @override
  Stream<DefibEvent> get events => _events.stream;

  @override
  Future<void> connect(ByteTransport transport) async {
    if (transport is! SimulatorTransport) {
      throw StateError('SimulatorDriver acceptă doar SimulatorTransport.');
    }
    _transport = transport;
    _state = DriverState.connecting;
    _sub = transport.incoming.listen(_onBytes);
    transport.start();
    _state = DriverState.connected;
  }

  void _onBytes(List<int> bytes) {
    _codec.feed(bytes);
    while (true) {
      final f = _codec.decodeNext();
      if (f == null) break;
      switch (f.type) {
        case SajFrameType.ecgBatch:
          final r = BinReader(f.payload);
          while (r.pos + 4 <= f.payload.length) {
            _ecg.add(r.f32());
          }
        case SajFrameType.vitals:
          if (f.payload.length >= 20) {
            final r = BinReader(f.payload);
            final ts = DateTime.fromMillisecondsSinceEpoch(r.i64());
            final hr = r.f32();
            final spo2 = r.f32();
            final etco2 = r.f32();
            _vitals.add(VitalsSample(
              timestamp: ts,
              heartRate: hr < 0 ? null : hr,
              spo2: spo2 < 0 ? null : spo2,
              etco2: etco2 < 0 ? null : etco2,
            ));
          }
        case SajFrameType.event:
          if (f.payload.length >= 11) {
            final r = BinReader(f.payload);
            final ts = DateTime.fromMillisecondsSinceEpoch(r.i64());
            final typeIdx = r.u8();
            final energy = r.u16();
            final type = typeIdx < DefibEventType.values.length
                ? DefibEventType.values[typeIdx]
                : DefibEventType.other;
            _events.add(DefibEvent(
              timestamp: ts,
              type: type,
              energyJoules: energy > 0 ? energy : null,
            ));
          }
        default:
          break; // ack/error/etc. - ignorate de driverul de simulare.
      }
    }
  }

  /// Trimite simulatorului o comandă de schimbare a ritmului.
  Future<void> setRhythm(SimRhythm rhythm) async {
    final b = Bin()
      ..u8(1)
      ..u8(rhythm.index);
    await _transport?.send(SajLinkCodec.encode(SajFrame(SajFrameType.command, b.take())));
  }

  /// Trimite simulatorului o comandă de administrare a unui șoc de test.
  Future<void> deliverShock({int joules = 150}) async {
    final b = Bin()
      ..u8(2)
      ..u16(joules);
    await _transport?.send(SajLinkCodec.encode(SajFrame(SajFrameType.command, b.take())));
  }

  @override
  Future<void> disconnect() async {
    _state = DriverState.disconnected;
    await _sub?.cancel();
    await _transport?.close();
  }
}
