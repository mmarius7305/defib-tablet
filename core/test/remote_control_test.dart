import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:defib_core/frames.dart';
import 'package:defib_core/mission.dart';
import 'package:defib_core/remote_control.dart';
import 'package:defib_core/sajlink_driver.dart';
import 'package:defib_core/simulator.dart';
import 'package:defib_core/tcp_transport.dart';

Future<void> _bridgeLikeSimServer(Socket socket) async {
  final device = SimulatorTransport();
  final sub = device.incoming.listen((bytes) {
    try {
      socket.add(bytes);
    } catch (_) {}
  });
  socket.listen(
    (data) {
      unawaited(device.send(List<int>.from(data)));
    },
    onDone: () async {
      await sub.cancel();
      await device.close();
    },
    onError: (_) async {
      await sub.cancel();
      await device.close();
    },
    cancelOnError: true,
  );
  device.start();
}

void main() {
  test('encodeSetRhythm / encodeDeliverShock produc cadre command valide', () {
    final rhythm = encodeSetRhythm(SimRhythm.vtach);
    final codec = SajLinkCodec()..feed(rhythm);
    final f = codec.decodeNext()!;
    expect(f.type, SajFrameType.command);
    expect(f.payload[0], SajCommand.setRhythm);
    expect(f.payload[1], SimRhythm.vtach.index);

    final shock = encodeDeliverShock(joules: 200);
    final c2 = SajLinkCodec()..feed(shock);
    final f2 = c2.decodeNext()!;
    expect(f2.type, SajFrameType.command);
    expect(f2.payload[0], SajCommand.deliverShock);
    expect(f2.payload[1] | (f2.payload[2] << 8), 200);
  });

  test('telecomandă TCP: șoc 200J peste sim_server loopback', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final clientDone = Completer<void>();
    server.listen((socket) {
      unawaited(_bridgeLikeSimServer(socket).whenComplete(clientDone.complete));
    });

    final transport = TcpTransport();
    await transport.connect('127.0.0.1', port);
    final driver = SajLinkDriver();
    await driver.connect(transport);

    final events = <dynamic>[];
    final sub = driver.events.listen(events.add);
    // Așteaptă primul flux ECG ca să fim siguri că bridge-ul a pornit.
    await driver.ecgMillivolts.first.timeout(const Duration(seconds: 2));
    await driver.deliverShock(joules: 200);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await sub.cancel();
    await driver.disconnect();
    await server.close();

    expect(events, isNotEmpty);
    expect(events.last.type.toString(), contains('shockDelivered'));
    expect(events.last.energyJoules, 200);
  });

  test('telecomandă TCP: schimbare ritm → rhythmAnalysis', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => unawaited(_bridgeLikeSimServer(socket)));

    final transport = TcpTransport();
    await transport.connect('127.0.0.1', server.port);
    final driver = SajLinkDriver();
    await driver.connect(transport);
    final events = <dynamic>[];
    final sub = driver.events.listen(events.add);
    await driver.ecgMillivolts.first.timeout(const Duration(seconds: 2));
    await driver.setRhythm(SimRhythm.asystole);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await sub.cancel();
    await driver.disconnect();
    await server.close();

    expect(events, isNotEmpty);
    expect(events.last.type.toString(), contains('rhythmAnalysis'));
  });

  test('MissionOfflineQueue: anti-dublu-click și FIFO', () {
    final q = MissionOfflineQueue(
        antiDoubleClick: const Duration(milliseconds: 500));
    final t0 = DateTime(2026, 11, 1, 12, 0, 0);
    expect(q.tryEnqueue(MissionTimeKey.plecareGaraj, '12:00', now: t0), isTrue);
    expect(
        q.tryEnqueue(MissionTimeKey.plecareGaraj, '12:00',
            now: t0.add(const Duration(milliseconds: 100))),
        isFalse);
    expect(
        q.tryEnqueue(MissionTimeKey.sosireAdresa, '12:10',
            now: t0.add(const Duration(seconds: 1))),
        isTrue);
    expect(q.length, 2);
    expect(q.dequeue()!.key, MissionTimeKey.plecareGaraj);
    expect(q.dequeue()!.key, MissionTimeKey.sosireAdresa);
    expect(q.length, 0);
  });

  test('MissionOfflineQueue persistă ca JSON', () {
    final q = MissionOfflineQueue();
    final t0 = DateTime(2026, 11, 1, 13, 0, 0);
    expect(
        q.tryEnqueue(MissionTimeKey.sosireSpital, '13:00', now: t0), isTrue);
    final raw = q.encode();
    final q2 = MissionOfflineQueue();
    q2.loadFrom(raw);
    expect(q2.length, 1);
    expect(q2.peek()!.key, MissionTimeKey.sosireSpital);
    expect(q2.peek()!.value, '13:00');
  });
}
