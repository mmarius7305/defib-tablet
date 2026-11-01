/// Server TCP SAJLink — panou/simulator remote pe portul 45678.
///
/// Rulează: `dart run tool/sim_server.dart [--port 45678]`
/// Fiecare client primește ECG + vitale și poate trimite comenzi 0x04
/// (ritm / șoc / auto-test). Date 100% sintetice.
library;

import 'dart:async';
import 'dart:io';

import 'package:defib_core/simulator.dart';

Future<void> main(List<String> args) async {
  var port = 45678;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    }
  }

  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('sim_server SAJLink pe ${server.address.address}:$port');

  await for (final socket in server) {
    stdout.writeln(
        'client ${socket.remoteAddress.address}:${socket.remotePort}');
    unawaited(_serveClient(socket));
  }
}

Future<void> _serveClient(Socket socket) async {
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
