/// Driver SAJLink peste orice [ByteTransport] (TCP, BLE, etc.).
///
/// Decodează cadrele primite (ECG, vitale, evenimente) și trimite comenzi
/// de telecomandă. Folosit când tableta se leagă la un simulator/aparat
/// remote, nu la [SimulatorTransport] in-process.
library;

import 'dart:async';

import 'connection.dart';
import 'frames.dart';
import 'models.dart';
import 'remote_control.dart';
import 'simulator.dart' show BinReader;

/// Driver client SAJLink cu telecomandă.
class SajLinkDriver implements DefibrillatorDriver, RemoteControllable {
  ByteTransport? _transport;
  final _codec = SajLinkCodec();

  final _vitals = StreamController<VitalsSample>.broadcast();
  final _ecg = StreamController<double>.broadcast();
  final _events = StreamController<DefibEvent>.broadcast();
  StreamSubscription<List<int>>? _sub;
  DriverState _state = DriverState.disconnected;

  @override
  String get name => 'SAJLink remote';

  @override
  DriverState get state => _state;

  @override
  int get ecgSampleRateHz => 250;

  @override
  Stream<VitalsSample> get vitals => _vitals.stream;

  @override
  Stream<double> get ecgMillivolts => _ecg.stream;

  @override
  Stream<DefibEvent> get events => _events.stream;

  @override
  bool get supportsRemoteControl =>
      _state == DriverState.connected && _transport != null;

  @override
  Future<void> connect(ByteTransport transport) async {
    _transport = transport;
    _state = DriverState.connecting;
    _sub = transport.incoming.listen(_onBytes, onError: (_) {
      _state = DriverState.error;
    });
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
          break;
      }
    }
  }

  @override
  Future<void> setRhythm(SimRhythm rhythm) async {
    await _transport?.send(encodeSetRhythm(rhythm));
  }

  @override
  Future<void> deliverShock({int joules = 150}) async {
    await _transport?.send(encodeDeliverShock(joules: joules));
  }

  @override
  Future<void> runSelfTest() async {
    await _transport?.send(encodeSelfTest());
  }

  @override
  Future<void> disconnect() async {
    _state = DriverState.disconnected;
    await _sub?.cancel();
    await _transport?.close();
    _transport = null;
  }
}
