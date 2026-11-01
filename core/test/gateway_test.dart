import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:defib_core/gateway_service.dart';
import 'package:defib_core/mission.dart';
import 'package:defib_core/simulator.dart';

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

Future<Map<String, dynamic>> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    dynamic decoded;
    if (body.isNotEmpty && body.trimLeft().startsWith('{')) {
      decoded = jsonDecode(body);
    }
    return {
      'status': res.statusCode,
      'body': decoded,
      'raw': body,
      'contentType': res.headers.contentType?.mimeType,
    };
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _httpPost(String url, Object payload) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return {
      'status': res.statusCode,
      'body': body.isEmpty ? null : jsonDecode(body),
    };
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('resolveMissionTimestamp MULTI-ZI peste miezul nopții', () {
    final a = resolveMissionTimestamp('23:50',
        now: DateTime(2026, 10, 25, 12));
    expect(a, DateTime(2026, 10, 25, 23, 50));
    final b = resolveMissionTimestamp('23:58', previous: a);
    expect(b, DateTime(2026, 10, 25, 23, 58));
    final c = resolveMissionTimestamp('00:05', previous: b);
    expect(c, DateTime(2026, 10, 26, 0, 5));
    final d = resolveMissionTimestamp('00:15', previous: c);
    expect(d.difference(c).inMinutes, 10);
  });

  test('gateway e2e: sim ↔ REST timpi + vitale + persistare', () async {
    final sim = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    sim.listen((s) => unawaited(_bridgeLikeSimServer(s)));

    final storeDir = await Directory.systemTemp.createTemp('gw_store_');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final httpPort = probe.port;
    await probe.close();

    final gw = GatewayService(
      sourceHost: '127.0.0.1',
      sourcePort: sim.port,
      httpPort: httpPort,
      storeDir: storeDir,
    );
    await gw.start();
    final base = 'http://127.0.0.1:$httpPort';

    // Așteaptă conectarea sursei + primul vitals.
    Map<String, dynamic>? health;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final h = await _httpGet('$base/api/v1/health');
      expect(h['status'], 200);
      health = h['body'] as Map<String, dynamic>;
      if (health['sursa_conectata'] == true) break;
    }
    expect(health!['sursa_conectata'], isTrue);
    expect(health['serviciu'], 'gateway-saj');

    Map<String, dynamic>? vitals;
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final v = await _httpGet('$base/api/v1/vitals/latest');
      vitals = v['body'] as Map<String, dynamic>;
      if (vitals['basic'] != null) break;
    }
    expect(vitals!['basic'], isNotNull);
    final hr = (vitals['basic'] as Map)['hr'] as num;
    expect(hr, greaterThan(50));
    expect(hr, lessThan(220));

    // Reset + 6 timpi overnight.
    final reset = await _httpPost('$base/api/v1/misiune/timpi', {'reset': true});
    expect(reset['status'], 200);
    final mid = (reset['body'] as Map)['misiune_id'] as String;
    expect(mid, startsWith('MSJ-'));

    final posts = <(String, String)>[
      (MissionTimeKey.plecareGaraj, '23:50'),
      (MissionTimeKey.sosireAdresa, '23:58'),
      (MissionTimeKey.plecareAdresa, '00:05'),
      (MissionTimeKey.sosireSpital, '00:15'),
      (MissionTimeKey.predarePacient, '00:22'),
      (MissionTimeKey.incheiereMisiune, '00:30'),
    ];
    for (final p in posts) {
      final r = await _httpPost('$base/api/v1/misiune/timpi', {
        'cheie': p.$1,
        'valoare': p.$2,
      });
      expect(r['status'], 200, reason: '${p.$1} -> ${r['body']}');
    }

    final bad = await _httpPost('$base/api/v1/misiune/timpi', {
      'cheie': 'nu_exista',
      'valoare': '12:00',
    });
    expect(bad['status'], 400);

    final timpi = await _httpGet('$base/api/v1/misiune/timpi');
    final body = timpi['body'] as Map<String, dynamic>;
    expect(body['multi_zi'], isTrue);
    final dur = body['durate_minute'] as Map;
    expect(dur['plecare_garaj->sosire_adresa'], 8.0);
    expect(dur['sosire_adresa->plecare_adresa'], 7.0);
    expect(dur['plecare_adresa->sosire_spital'], 10.0);
    expect(dur['sosire_spital->predare_pacient'], 7.0);
    expect(dur['predare_pacient->incheiere_misiune'], 8.0);

    final xml = await _httpGet('$base/api/v1/caz/xml112');
    expect(xml['status'], 200);
    expect(xml['raw'] as String, contains('plecare_garaj'));
    expect(xml['raw'] as String, contains(mid));

    // WS snapshot.
    final ws = await WebSocket.connect('ws://127.0.0.1:$httpPort/ws/live');
    final first = await ws.first.timeout(const Duration(seconds: 2));
    final snap = jsonDecode(first as String) as Map<String, dynamic>;
    expect(snap['type'], 'snapshot');
    expect(snap['sursa_conectata'], isTrue);
    await ws.close();

    // SSE content-type.
    final client = HttpClient();
    final sseReq =
        await client.getUrl(Uri.parse('$base/api/v1/stream/sse'));
    final sseRes = await sseReq.close();
    expect(sseRes.headers.contentType?.mimeType, 'text/event-stream');
    final sseChunk = await sseRes
        .transform(utf8.decoder)
        .first
        .timeout(const Duration(seconds: 2));
    expect(sseChunk, contains('snapshot'));
    client.close(force: true);

    // Persistare: stop + restart pe același store.
    await gw.stop();
    await sim.close();

    final sim2 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    sim2.listen((s) => unawaited(_bridgeLikeSimServer(s)));
    final probe2 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final httpPort2 = probe2.port;
    await probe2.close();

    final gw2 = GatewayService(
      sourceHost: '127.0.0.1',
      sourcePort: sim2.port,
      httpPort: httpPort2,
      storeDir: storeDir,
    );
    await gw2.start();
    final restored =
        await _httpGet('http://127.0.0.1:$httpPort2/api/v1/misiune/timpi');
    final rb = restored['body'] as Map<String, dynamic>;
    expect(rb['misiune_id'], mid);
    expect(rb['multi_zi'], isTrue);
    expect((rb['timpi'] as Map)['incheiere_misiune'], isNotNull);

    // Client MissionOfflineQueue → gateway.
    final q = MissionOfflineQueue();
    expect(q.tryEnqueue(MissionTimeKey.plecareGaraj, '10:00'), isTrue);
    final gClient =
        GatewayClient(baseUrl: 'http://127.0.0.1:$httpPort2');
    await _httpPost('http://127.0.0.1:$httpPort2/api/v1/misiune/timpi',
        {'reset': true});
    while (q.peek() != null) {
      final item = q.peek()!;
      await gClient.postMissionTime(key: item.key, value: item.value);
      q.dequeue();
    }
    final after = await gClient.getMissionTimes();
    expect(after['timpi'], isNotNull);
    expect((after['timpi'] as Map)['plecare_garaj'], isNotNull);
    gClient.close();

    await gw2.stop();
    await sim2.close();
    await storeDir.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
