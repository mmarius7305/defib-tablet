/// Modele și coadă offline pentru timpii de misiune (B44-O5 / 17B).
///
/// Tableta postează cheile canonice pe gateway (`POST /api/v1/misiune/timpi`).
/// Fără IP-uri hardcodate — baza URL e injectată. Date 100% operaționale
/// (ore), fără date de pacient.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cele 6 chei canonice din 17B / PK_TIMPI.
class MissionTimeKey {
  static const plecareGaraj = 'plecare_garaj';
  static const sosireAdresa = 'sosire_adresa';
  static const plecareAdresa = 'plecare_adresa';
  static const sosireSpital = 'sosire_spital';
  static const predarePacient = 'predare_pacient';
  static const incheiereMisiune = 'incheiere_misiune';

  static const List<String> ordered = [
    plecareGaraj,
    sosireAdresa,
    plecareAdresa,
    sosireSpital,
    predarePacient,
    incheiereMisiune,
  ];
}

/// Starea conexiunii tabletei față de gateway.
enum LinkMode { offline, online, storeAndForward }

/// O înregistrare de timp așteptând trimitere (coadă locală).
class PendingTimePost {
  final String key;
  final String value; // HH:mm sau ISO
  final DateTime queuedAt;

  const PendingTimePost({
    required this.key,
    required this.value,
    required this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
        'cheie': key,
        'valoare': value,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory PendingTimePost.fromJson(Map<String, dynamic> j) => PendingTimePost(
        key: j['cheie'] as String,
        value: j['valoare'] as String,
        queuedAt: DateTime.parse(j['queued_at'] as String),
      );
}

/// Coadă FIFO locală, anti-dublu-click pe cheie.
class MissionOfflineQueue {
  final List<PendingTimePost> _items = [];
  final Map<String, DateTime> _lastClick = {};
  final Duration antiDoubleClick;

  MissionOfflineQueue(
      {this.antiDoubleClick = const Duration(milliseconds: 800)});

  List<PendingTimePost> get items => List.unmodifiable(_items);

  int get length => _items.length;

  /// Returnează `false` dacă apăsarea e prea rapidă (anti-dublu-click).
  bool tryEnqueue(String key, String value, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final last = _lastClick[key];
    if (last != null && t.difference(last) < antiDoubleClick) {
      return false;
    }
    _lastClick[key] = t;
    _items.add(PendingTimePost(key: key, value: value, queuedAt: t));
    return true;
  }

  PendingTimePost? peek() => _items.isEmpty ? null : _items.first;

  PendingTimePost? dequeue() => _items.isEmpty ? null : _items.removeAt(0);

  void clear() {
    _items.clear();
    _lastClick.clear();
  }

  String encode() => jsonEncode(_items.map((e) => e.toJson()).toList());

  void loadFrom(String raw) {
    _items.clear();
    final list = jsonDecode(raw) as List<dynamic>;
    for (final e in list) {
      _items.add(PendingTimePost.fromJson(e as Map<String, dynamic>));
    }
  }
}

/// Client HTTP minimal pentru gateway-ul 17B (LAN).
class GatewayClient {
  final String baseUrl; // ex. http://127.0.0.1:8089 — setat din UI
  final HttpClient _http;
  final Duration timeout;

  GatewayClient({
    required this.baseUrl,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 3),
  }) : _http = httpClient ?? HttpClient();

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, dynamic>> getHealth() async {
    final req = await _http.getUrl(_uri('/api/v1/health')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('health ${res.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getLatestVitals() async {
    final req =
        await _http.getUrl(_uri('/api/v1/vitals/latest')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('vitals ${res.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMissionTimes() async {
    final req =
        await _http.getUrl(_uri('/api/v1/misiune/timpi')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('timpi ${res.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Setează un timp. [value] = `HH:mm` sau ISO. Returnează corpul JSON.
  Future<Map<String, dynamic>> postMissionTime({
    required String key,
    required String value,
  }) async {
    final req =
        await _http.postUrl(_uri('/api/v1/misiune/timpi')).timeout(timeout);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'cheie': key, 'valoare': value}));
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('post timpi ${res.statusCode}: $body');
    }
    return body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
  }

  void close() => _http.close(force: true);
}

/// Formatează ora curentă ca `HH:mm` (local).
String formatHhMm([DateTime? now]) {
  final t = now ?? DateTime.now();
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Etichete UI pentru butoanele O5 (5 butoane + predare).
class MissionButtonSpec {
  final String label;
  final String key;
  const MissionButtonSpec(this.label, this.key);

  static const List<MissionButtonSpec> crewButtons = [
    MissionButtonSpec('PLECARE', MissionTimeKey.plecareGaraj),
    MissionButtonSpec('SOSIRE', MissionTimeKey.sosireAdresa),
    MissionButtonSpec('PLECARE CAZ', MissionTimeKey.plecareAdresa),
    MissionButtonSpec('SPITAL', MissionTimeKey.sosireSpital),
    MissionButtonSpec('PREDARE', MissionTimeKey.predarePacient),
    MissionButtonSpec('LIBER', MissionTimeKey.incheiereMisiune),
  ];
}
