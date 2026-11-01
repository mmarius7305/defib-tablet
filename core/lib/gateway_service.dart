/// Gateway B44-O2 (17B): client TCP SJL1 → REST/WS/SSE pe LAN.
///
/// Zero IP-uri de producție, zero secrete. Date sintetice / operaționale.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'frames.dart';
import 'mission.dart';
import 'models.dart';
import 'simulator.dart' show BinReader;

const String kGatewayVersion = '0.02';
const String kGatewayServiceName = 'gateway-saj';

/// Rezolvă `HH:mm` sau ISO cu regula MULTI-ZI (17B §4.3).
DateTime resolveMissionTimestamp(
  String value, {
  DateTime? previous,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  if (value.contains('T')) {
    return DateTime.parse(value);
  }
  final parts = value.split(':');
  if (parts.length < 2) {
    throw FormatException('valoare timp invalidă: $value');
  }
  final h = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  if (h < 0 || h > 23 || m < 0 || m > 59) {
    throw FormatException('valoare timp invalidă: $value');
  }
  if (previous == null) {
    return DateTime(t.year, t.month, t.day, h, m);
  }
  var candidate =
      DateTime(previous.year, previous.month, previous.day, h, m);
  while (!candidate.isAfter(previous)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

Map<String, double> computeDurationsMinutes(Map<String, DateTime?> timpi) {
  final out = <String, double>{};
  for (var i = 0; i < MissionTimeKey.ordered.length - 1; i++) {
    final a = MissionTimeKey.ordered[i];
    final b = MissionTimeKey.ordered[i + 1];
    final ta = timpi[a];
    final tb = timpi[b];
    if (ta != null && tb != null) {
      out['$a->$b'] = tb.difference(ta).inMilliseconds / 60000.0;
    }
  }
  return out;
}

bool isMultiDay(Map<String, DateTime?> timpi) {
  DateTime? first;
  DateTime? last;
  for (final k in MissionTimeKey.ordered) {
    final v = timpi[k];
    if (v == null) continue;
    first ??= v;
    last = v;
  }
  if (first == null || last == null) return false;
  return first.year != last.year ||
      first.month != last.month ||
      first.day != last.day;
}

String _iso(DateTime dt) => dt.toIso8601String();

String _pupilsName(int code) {
  if (code < 0 || code >= PupilsStatus.values.length) return 'unknown';
  return PupilsStatus.values[code].name;
}

/// Inel limitat + append pe disc (JSON Lines).
class StoreAndForward {
  final Directory dir;
  final int ringLimit;
  final Queue<Map<String, dynamic>> ring = Queue();
  IOSink? _sink;
  late final File _jsonl;

  StoreAndForward(this.dir, {this.ringLimit = 3600}) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _jsonl = File('${dir.path}/gateway_store.jsonl');
  }

  Future<void> open() async {
    if (_jsonl.existsSync()) {
      final lines = await _jsonl.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          _pushRing(m);
        } catch (_) {}
      }
    }
    _sink = _jsonl.openWrite(mode: FileMode.append);
  }

  void _pushRing(Map<String, dynamic> m) {
    ring.addLast(m);
    while (ring.length > ringLimit) {
      ring.removeFirst();
    }
  }

  void append(Map<String, dynamic> message) {
    _pushRing(message);
    final sink = _sink;
    if (sink != null) {
      sink.writeln(jsonEncode(message));
    }
  }

  Future<void> flush() async => _sink?.flush();

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  List<Map<String, dynamic>> recentOfType(String type, int n) {
    final out = <Map<String, dynamic>>[];
    for (final m in ring.toList().reversed) {
      if (m['type'] == type) {
        out.add(m);
        if (out.length >= n) break;
      }
    }
    return out.reversed.toList();
  }
}

class MissionState {
  String? misiuneId;
  int dailyCounter;
  String counterDay; // YYYYMMDD
  final Map<String, DateTime?> timpi = {
    for (final k in MissionTimeKey.ordered) k: null,
  };

  MissionState({this.misiuneId, this.dailyCounter = 0, String? counterDay})
      : counterDay = counterDay ?? _dayKey(DateTime.now());

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'misiune_id': misiuneId,
        'daily_counter': dailyCounter,
        'counter_day': counterDay,
        'timpi': {
          for (final e in timpi.entries)
            e.key: e.value?.toIso8601String(),
        },
      };

  factory MissionState.fromJson(Map<String, dynamic> j) {
    final s = MissionState(
      misiuneId: j['misiune_id'] as String?,
      dailyCounter: (j['daily_counter'] as num?)?.toInt() ?? 0,
      counterDay: j['counter_day'] as String? ?? _dayKey(DateTime.now()),
    );
    final map = j['timpi'];
    if (map is Map) {
      for (final k in MissionTimeKey.ordered) {
        final v = map[k];
        if (v is String && v.isNotEmpty) {
          s.timpi[k] = DateTime.parse(v);
        }
      }
    }
    return s;
  }

  String reset({DateTime? now}) {
    final t = now ?? DateTime.now();
    final day = _dayKey(t);
    if (day != counterDay) {
      counterDay = day;
      dailyCounter = 0;
    }
    dailyCounter += 1;
    misiuneId =
        'MSJ-$day-${dailyCounter.toString().padLeft(3, '0')}';
    for (final k in MissionTimeKey.ordered) {
      timpi[k] = null;
    }
    return misiuneId!;
  }

  Map<String, dynamic> snapshot() {
    final times = <String, String?>{
      for (final k in MissionTimeKey.ordered)
        k: timpi[k]?.toIso8601String(),
    };
    return {
      'misiune_id': misiuneId,
      'timpi': times,
      'multi_zi': isMultiDay(timpi),
      'durate_minute': computeDurationsMinutes(timpi),
    };
  }
}

/// Serviciul gateway: TCP sursă + HTTP REST/WS/SSE.
class GatewayService {
  final String sourceHost;
  final int sourcePort;
  final int httpPort;
  final Directory storeDir;

  late final StoreAndForward store;
  late MissionState mission;
  HttpServer? _http;
  Socket? _source;
  StreamSubscription<Uint8List>? _sourceSub;
  bool _running = false;
  bool sourceConnected = false;
  DateTime? lastFrameAt;
  int _backoffSec = 1;

  Map<String, dynamic>? latestBasic;
  Map<String, dynamic>? latestExtended;
  final List<double> _ecgRing = [];
  static const int _ecgRingMax = 250 * 30; // 30 s
  final List<Map<String, dynamic>> _events = [];

  final Set<WebSocket> _wsClients = {};
  final Set<HttpResponse> _sseClients = {};

  GatewayService({
    required this.sourceHost,
    required this.sourcePort,
    required this.httpPort,
    required this.storeDir,
  });

  int get wsClients => _wsClients.length;
  int get sseClients => _sseClients.length;

  File get _missionFile => File('${storeDir.path}/misiune.json');

  Future<void> start() async {
    store = StoreAndForward(storeDir);
    await store.open();
    if (_missionFile.existsSync()) {
      try {
        mission = MissionState.fromJson(
            jsonDecode(await _missionFile.readAsString())
                as Map<String, dynamic>);
      } catch (_) {
        mission = MissionState();
      }
    } else {
      mission = MissionState();
      // Restaurează misiunea din jsonl dacă există mesaje misiune.
      for (final m in store.ring) {
        if (m['type'] == 'misiune' && m['misiune'] is Map) {
          final snap = m['misiune'] as Map;
          mission.misiuneId = snap['misiune_id'] as String?;
          final timpi = snap['timpi'];
          if (timpi is Map) {
            for (final k in MissionTimeKey.ordered) {
              final v = timpi[k];
              if (v is String && v.isNotEmpty) {
                mission.timpi[k] = DateTime.parse(v);
              }
            }
          }
        }
      }
    }
    if (mission.misiuneId == null) {
      mission.reset();
      await _persistMission();
    }

    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, httpPort);
    _running = true;
    _http!.listen(_onHttp, onError: (_) {});
    unawaited(_sourceLoop());
  }

  Future<void> stop() async {
    _running = false;
    await _sourceSub?.cancel();
    _sourceSub = null;
    try {
      await _source?.close();
    } catch (_) {}
    _source = null;
    sourceConnected = false;
    for (final ws in _wsClients.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _wsClients.clear();
    for (final r in _sseClients.toList()) {
      try {
        await r.close();
      } catch (_) {}
    }
    _sseClients.clear();
    await store.flush();
    await store.close();
    await _persistMission();
    await _http?.close(force: true);
    _http = null;
  }

  Future<void> _persistMission() async {
    if (!storeDir.existsSync()) storeDir.createSync(recursive: true);
    await _missionFile.writeAsString(jsonEncode(mission.toJson()));
  }

  Future<void> _sourceLoop() async {
    while (_running) {
      try {
        final socket = await Socket.connect(
          sourceHost,
          sourcePort,
          timeout: const Duration(seconds: 3),
        );
        _source = socket;
        sourceConnected = true;
        _backoffSec = 1;
        // Codec proaspăt pe fiecare conexiune (buffer curat).
        final codec = SajLinkCodec();
        _sourceSub = socket.listen(
          (data) {
            lastFrameAt = DateTime.now();
            codec.feed(data);
            while (true) {
              final f = codec.decodeNext();
              if (f == null) break;
              _onFrame(f);
            }
          },
          onDone: () {
            sourceConnected = false;
            _source = null;
          },
          onError: (_) {
            sourceConnected = false;
            _source = null;
          },
          cancelOnError: true,
        );
        // Wait until disconnected.
        while (_running && sourceConnected) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await _sourceSub?.cancel();
        _sourceSub = null;
        try {
          await socket.close();
        } catch (_) {}
      } catch (_) {
        sourceConnected = false;
      }
      if (!_running) break;
      await Future<void>.delayed(Duration(seconds: _backoffSec));
      _backoffSec = math.min(30, _backoffSec * 2);
    }
  }

  void _onFrame(SajFrame f) {
    switch (f.type) {
      case SajFrameType.vitals:
        if (f.payload.length >= 20) {
          final r = BinReader(f.payload);
          final ts = DateTime.fromMillisecondsSinceEpoch(r.i64());
          final hr = r.f32();
          final spo2 = r.f32();
          final etco2 = r.f32();
          final msg = {
            'type': 'vitals',
            'ts': _iso(ts),
            'hr': hr < 0 ? null : hr,
            'spo2': spo2 < 0 ? null : spo2,
            'etco2': etco2 < 0 ? null : etco2,
          };
          latestBasic = msg;
          store.append(msg);
          _broadcast(msg);
        }
      case SajFrameType.ecgBatch:
        final r = BinReader(f.payload);
        final mv = <double>[];
        while (r.pos + 4 <= f.payload.length) {
          final v = r.f32();
          mv.add(v);
          _ecgRing.add(v);
          while (_ecgRing.length > _ecgRingMax) {
            _ecgRing.removeAt(0);
          }
        }
        if (mv.isNotEmpty) {
          _broadcast({'type': 'ecg', 'mv': mv});
        }
      case SajFrameType.event:
        if (f.payload.length >= 11) {
          final r = BinReader(f.payload);
          final ts = DateTime.fromMillisecondsSinceEpoch(r.i64());
          final typeIdx = r.u8();
          final energy = r.u16();
          final type = typeIdx < DefibEventType.values.length
              ? DefibEventType.values[typeIdx].name
              : 'other';
          final msg = {
            'type': 'event',
            'ts': _iso(ts),
            'event': type,
            'energy_joules': energy > 0 ? energy : null,
          };
          _events.add(msg);
          if (_events.length > 200) _events.removeAt(0);
          store.append(msg);
          _broadcast(msg);
        }
      case SajFrameType.extendedVitals:
        if (f.payload.length >= 22) {
          final r = BinReader(f.payload);
          final ts = DateTime.fromMillisecondsSinceEpoch(r.i64());
          final tas = r.u16();
          final tad = r.u16();
          final fr = r.u16();
          final temp = r.f32();
          final glu = r.u16();
          final gcs = r.u8();
          final pup = r.u8();
          int? map;
          int? tasO = tas == 0xFFFF ? null : tas;
          int? tadO = tad == 0xFFFF ? null : tad;
          if (tasO != null && tadO != null) {
            map = ((tasO + 2 * tadO) / 3).round();
          }
          final msg = {
            'type': 'ext_vitals',
            'ts': _iso(ts),
            'tas': tasO,
            'tad': tadO,
            'map': map,
            'fr': fr == 0xFFFF ? null : fr.toDouble(),
            'temp': temp < 0 ? null : temp,
            'glicemie': glu == 0xFFFF ? null : glu.toDouble(),
            'gcs': gcs == 0xFF ? null : gcs,
            'pupile': pup == 0xFF ? null : _pupilsName(pup),
          };
          latestExtended = msg;
          store.append(msg);
          _broadcast(msg);
        }
      default:
        break;
    }
  }

  void _broadcast(Map<String, dynamic> msg) {
    final raw = jsonEncode(msg);
    for (final ws in _wsClients.toList()) {
      try {
        ws.add(raw);
      } catch (_) {
        _wsClients.remove(ws);
      }
    }
    final sse = 'data: $raw\n\n';
    for (final res in _sseClients.toList()) {
      try {
        res.write(sse);
      } catch (_) {
        _sseClients.remove(res);
      }
    }
  }

  Future<void> _onHttp(HttpRequest request) async {
    final path = request.uri.path;
    if (WebSocketTransformer.isUpgradeRequest(request) &&
        (path == '/ws/live' || path == '/api/v1/ws/live')) {
      final ws = await WebSocketTransformer.upgrade(request);
      _wsClients.add(ws);
      ws.add(jsonEncode(_snapshotMessage()));
      ws.listen(
        (_) {},
        onDone: () => _wsClients.remove(ws),
        onError: (_) => _wsClients.remove(ws),
        cancelOnError: true,
      );
      return;
    }

    if (path == '/api/v1/stream/sse') {
      request.response.bufferOutput = false;
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.headers.set('Connection', 'keep-alive');
      _sseClients.add(request.response);
      request.response.write('data: ${jsonEncode(_snapshotMessage())}\n\n');
      await request.response.flush();
      request.response.done.then((_) => _sseClients.remove(request.response));
      return;
    }

    try {
      if (path == '/api/v1/health' && request.method == 'GET') {
        await _json(request, 200, {
          'serviciu': kGatewayServiceName,
          'versiune': kGatewayVersion,
          'sursa_conectata': sourceConnected,
          'ws_clienti': wsClients,
          'sse_clienti': sseClients,
          'misiune_id': mission.misiuneId,
          'ora': _iso(DateTime.now()),
        });
      } else if (path == '/api/v1/vitals/latest' && request.method == 'GET') {
        await _json(request, 200, {
          'basic': latestBasic == null
              ? null
              : {
                  'ts': latestBasic!['ts'],
                  'hr': latestBasic!['hr'],
                  'spo2': latestBasic!['spo2'],
                  'etco2': latestBasic!['etco2'],
                },
          'extended': latestExtended == null
              ? null
              : {
                  'ts': latestExtended!['ts'],
                  'tas': latestExtended!['tas'],
                  'tad': latestExtended!['tad'],
                  'map': latestExtended!['map'],
                  'fr': latestExtended!['fr'],
                  'temp': latestExtended!['temp'],
                  'glicemie': latestExtended!['glicemie'],
                  'gcs': latestExtended!['gcs'],
                  'pupile': latestExtended!['pupile'],
                },
          'sursa': {
            'conectata': sourceConnected,
            'ultima_cadru': lastFrameAt == null ? null : _iso(lastFrameAt!),
          },
        });
      } else if (path == '/api/v1/misiune/timpi' && request.method == 'GET') {
        await _json(request, 200, mission.snapshot());
      } else if (path == '/api/v1/misiune/timpi' && request.method == 'POST') {
        await _handlePostTimpi(request);
      } else if (path == '/api/v1/caz/xml112' && request.method == 'GET') {
        final xml = _buildXml112();
        request.response.statusCode = 200;
        request.response.headers.contentType =
            ContentType('application', 'xml', charset: 'utf-8');
        request.response.write(xml);
        await request.response.close();
      } else {
        await _json(request, 404, {'error': 'not_found', 'path': path});
      }
    } catch (e) {
      await _json(request, 500, {'error': e.toString()});
    }
  }

  Future<void> _handlePostTimpi(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      await _json(request, 400, {'error': 'json_invalid'});
      return;
    }
    if (data['reset'] == true) {
      mission.reset();
      await _persistMission();
      final snap = mission.snapshot();
      final msg = {'type': 'misiune', 'misiune': snap};
      store.append(msg);
      _broadcast(msg);
      await _json(request, 200, snap);
      return;
    }
    final key = data['cheie'] as String?;
    final value = data['valoare'] as String?;
    if (key == null || value == null || !MissionTimeKey.ordered.contains(key)) {
      await _json(request, 400, {'error': 'cheie_sau_valoare_invalida'});
      return;
    }
    DateTime? previous;
    for (final k in MissionTimeKey.ordered) {
      if (k == key) break;
      if (mission.timpi[k] != null) previous = mission.timpi[k];
    }
    // Dacă cheia e re-setată, folosește timpul anterior din lanț.
    final idx = MissionTimeKey.ordered.indexOf(key);
    for (var i = idx - 1; i >= 0; i--) {
      final t = mission.timpi[MissionTimeKey.ordered[i]];
      if (t != null) {
        previous = t;
        break;
      }
    }
    DateTime resolved;
    try {
      resolved = resolveMissionTimestamp(value, previous: previous);
    } catch (_) {
      await _json(request, 400, {'error': 'valoare_invalida'});
      return;
    }
    if (previous != null && !resolved.isAfter(previous)) {
      await _json(request, 400, {'error': 'ordine_cronologica'});
      return;
    }
    mission.timpi[key] = resolved;
    await _persistMission();
    final snap = mission.snapshot();
    final msg = {'type': 'misiune', 'misiune': snap};
    store.append(msg);
    _broadcast(msg);
    await _json(request, 200, snap);
  }

  Map<String, dynamic> _snapshotMessage() => {
        'type': 'snapshot',
        'misiune': mission.snapshot(),
        'vitale_basic': latestBasic,
        'vitale_extinse': latestExtended,
        'istoric_vitale': store.recentOfType('vitals', 60),
        'istoric_eveninte': List<Map<String, dynamic>>.from(_events),
        'sursa_conectata': sourceConnected,
      };

  String _buildXml112() {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<caz112 version="0.02-draft" xmlns:u40="urn:saj:caz112">');
    buf.writeln(
        '  <misiune id="${mission.misiuneId ?? ''}" multi_zi="${isMultiDay(mission.timpi)}">');
    for (final k in MissionTimeKey.ordered) {
      final v = mission.timpi[k];
      if (v != null) {
        buf.writeln(
            '    <timp nume="$k" ora="${v.toIso8601String()}"/>');
      }
    }
    buf.writeln('  </misiune>');
    buf.writeln('  <durate unitate="minute">');
    for (final e in computeDurationsMinutes(mission.timpi).entries) {
      buf.writeln(
          '    <durata segment="${e.key}" minute="${e.value}"/>');
    }
    buf.writeln('  </durate>');
    buf.writeln('  <vitale>');
    if (latestBasic != null) {
      final hr = latestBasic!['hr'];
      final spo2 = latestBasic!['spo2'];
      final etco2 = latestBasic!['etco2'];
      if (hr != null) buf.writeln('    <fc bpm="$hr"/>');
      if (spo2 != null) buf.writeln('    <spo2 proc="$spo2"/>');
      if (etco2 != null) buf.writeln('    <etco2 mmhg="$etco2"/>');
    }
    if (latestExtended != null) {
      final x = latestExtended!;
      if (x['tas'] != null) buf.writeln('    <tas mmhg="${x['tas']}"/>');
      if (x['tad'] != null) buf.writeln('    <tad mmhg="${x['tad']}"/>');
      if (x['fr'] != null) buf.writeln('    <fr resp_min="${x['fr']}"/>');
      if (x['temp'] != null) buf.writeln('    <temp c="${x['temp']}"/>');
      if (x['glicemie'] != null) {
        buf.writeln('    <glicemie mg_dl="${x['glicemie']}"/>');
      }
      if (x['gcs'] != null) buf.writeln('    <gcs scor="${x['gcs']}"/>');
      if (x['pupile'] != null) {
        buf.writeln('    <pupile stare="${x['pupile']}"/>');
      }
    }
    buf.writeln('  </vitale>');
    buf.writeln('  <eveninte>');
    for (final e in _events) {
      buf.writeln(
          '    <eveniment tip="${e['event']}" ora="${e['ts']}" energie="${e['energy_joules'] ?? ''}"/>');
    }
    buf.writeln('  </eveninte>');
    buf.writeln('</caz112>');
    return buf.toString();
  }

  Future<void> _json(
      HttpRequest request, int code, Map<String, dynamic> body) async {
    request.response.statusCode = code;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
