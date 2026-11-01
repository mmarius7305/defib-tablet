/// Transport TCP pentru SAJLink (LAN/VPN izolat).
///
/// Clientul se conectează la un server de tip `sim_server` (port implicit 45678)
/// sau la un gateway care expune fluxul binar. Fără IP-uri de producție —
/// adresa e configurată la runtime.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'connection.dart';

/// [ByteTransport] peste un [Socket] TCP.
class TcpTransport implements ByteTransport {
  final _incoming = StreamController<List<int>>.broadcast();
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  /// Conectează la [host]:[port] (timeout implicit 5 s).
  Future<void> connect(String host, int port,
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (_open) await close();
    final socket = await Socket.connect(host, port, timeout: timeout);
    _socket = socket;
    _sub = socket.listen(
      (data) => _incoming.add(List<int>.from(data)),
      onError: (Object e, StackTrace st) {
        if (!_incoming.isClosed) _incoming.addError(e, st);
      },
      onDone: () {
        _open = false;
      },
      cancelOnError: false,
    );
    _open = true;
  }

  @override
  Future<void> send(List<int> data) async {
    final s = _socket;
    if (!_open || s == null) {
      throw StateError('TcpTransport nu este conectat.');
    }
    s.add(data);
    await s.flush();
  }

  @override
  Future<void> close() async {
    _open = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
