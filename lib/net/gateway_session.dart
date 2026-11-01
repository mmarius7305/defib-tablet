import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:defib_core/mission.dart';

/// Sesiune tableta ↔ gateway: stare link, misiune, coadă offline.
class GatewaySession extends ChangeNotifier {
  GatewayClient? _client;
  final MissionOfflineQueue queue = MissionOfflineQueue();
  LinkMode linkMode = LinkMode.offline;
  String statusMessage = 'Gateway: offline';
  String? misiuneId;
  String? liveHr;
  String? liveSpo2;
  String? liveEtco2;
  Map<String, String?> timpi = {
    for (final k in MissionTimeKey.ordered) k: null,
  };
  bool _flushing = false;
  bool _busyKey = false;
  Timer? _poll;

  String baseUrl = 'http://127.0.0.1:8089';

  bool get isBusy => _busyKey;

  /// Rând scurt de vitale de bază, din ultimul poll REST.
  String? get liveVitalsLabel {
    if (liveHr == null && liveSpo2 == null && liveEtco2 == null) return null;
    return 'FC ${liveHr ?? "—"} · SpO₂ ${liveSpo2 ?? "—"} · EtCO₂ ${liveEtco2 ?? "—"}';
  }

  Future<void> configure(String url) async {
    baseUrl = url.trim();
    _client?.close();
    _client = GatewayClient(baseUrl: baseUrl);
    await refresh();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final client = _client;
    if (client == null) return;
    try {
      final health = await client.getHealth();
      final connected = health['sursa_conectata'] == true;
      linkMode = connected ? LinkMode.online : LinkMode.storeAndForward;
      final misiune = await client.getMissionTimes();
      misiuneId = misiune['misiune_id'] as String?;
      final map = misiune['timpi'];
      if (map is Map) {
        for (final k in MissionTimeKey.ordered) {
          final v = map[k];
          timpi[k] = v?.toString();
        }
      }
      statusMessage = linkMode == LinkMode.online
          ? 'ONLINE${misiuneId != null ? " · $misiuneId" : ""}'
          : 'STORE-AND-FORWARD${misiuneId != null ? " · $misiuneId" : ""}';
      await _refreshVitals(client);
      await _flushQueue();
    } catch (_) {
      linkMode = queue.length > 0 ? LinkMode.storeAndForward : LinkMode.offline;
      statusMessage = linkMode == LinkMode.storeAndForward
          ? 'STORE-AND-FORWARD · coadă ${queue.length}'
          : 'OFFLINE · gateway inaccesibil';
    }
    notifyListeners();
  }

  /// Apasă un buton de timp O5. Anti-dublu-click + coadă offline.
  Future<bool> pressTimeButton(String key) async {
    if (_busyKey) return false;
    _busyKey = true;
    notifyListeners();
    final value = formatHhMm();
    final accepted = queue.tryEnqueue(key, value);
    if (!accepted) {
      _busyKey = false;
      notifyListeners();
      return false;
    }
    // Optimistic local update.
    timpi[key] = value;
    notifyListeners();
    await _flushQueue();
    _busyKey = false;
    notifyListeners();
    return true;
  }

  Future<void> _refreshVitals(GatewayClient client) async {
    try {
      final vitals = await client.getLatestVitals();
      final basic = vitals['basic'];
      if (basic is Map) {
        liveHr = _fmtNum(basic['hr'], 0);
        liveSpo2 = _fmtNum(basic['spo2'], 0);
        liveEtco2 = _fmtNum(basic['etco2'], 1);
      }
    } catch (_) {}
  }

  static String? _fmtNum(Object? raw, int digits) {
    if (raw == null) return null;
    final n = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
    if (n == null) return null;
    return n.toStringAsFixed(digits);
  }

  Future<void> _flushQueue() async {
    if (_flushing) return;
    final client = _client;
    if (client == null) return;
    _flushing = true;
    try {
      while (queue.peek() != null) {
        final item = queue.peek()!;
        try {
          await client.postMissionTime(key: item.key, value: item.value);
          queue.dequeue();
          linkMode = LinkMode.online;
        } catch (_) {
          linkMode = LinkMode.storeAndForward;
          statusMessage = 'STORE-AND-FORWARD · coadă ${queue.length}';
          break;
        }
      }
      if (queue.length == 0 && linkMode != LinkMode.offline) {
        try {
          final misiune = await client.getMissionTimes();
          misiuneId = misiune['misiune_id'] as String?;
          final map = misiune['timpi'];
          if (map is Map) {
            for (final k in MissionTimeKey.ordered) {
              final v = map[k];
              timpi[k] = v?.toString();
            }
          }
          statusMessage =
              'ONLINE${misiuneId != null ? " · $misiuneId" : ""}';
          linkMode = LinkMode.online;
        } catch (_) {}
      }
    } finally {
      _flushing = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client?.close();
    super.dispose();
  }
}
