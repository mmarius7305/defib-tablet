/// Gateway B44-O2 (17B) — REST + WS + SSE pe LAN, client TCP SJL1.
///
/// ```bash
/// dart run tool/gateway.dart --source 127.0.0.1:45678 --http 8089 --store ./gateway_store
/// dart compile exe tool/gateway.dart -o gateway
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:defib_core/gateway_service.dart';

Future<void> main(List<String> args) async {
  var sourceHost = '127.0.0.1';
  var sourcePort = 45678;
  var httpPort = 8089;
  var storePath = './gateway_store';

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--source' && i + 1 < args.length) {
      final sp = args[++i].split(':');
      sourceHost = sp[0];
      if (sp.length > 1) sourcePort = int.parse(sp[1]);
    } else if (a == '--http' && i + 1 < args.length) {
      httpPort = int.parse(args[++i]);
    } else if (a == '--store' && i + 1 < args.length) {
      storePath = args[++i];
    } else if (a == '--help' || a == '-h') {
      stdout.writeln(
          'usage: gateway [--source host:port] [--http port] [--store dir]');
      exit(0);
    }
  }

  final gw = GatewayService(
    sourceHost: sourceHost,
    sourcePort: sourcePort,
    httpPort: httpPort,
    storeDir: Directory(storePath),
  );

  await gw.start();
  stdout.writeln(
      'gateway-saj $kGatewayVersion  http=127.0.0.1:$httpPort  '
      'source=$sourceHost:$sourcePort  store=$storePath');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('oprire…');
    await gw.stop();
    exit(0);
  });
  try {
    ProcessSignal.sigterm.watch().listen((_) async {
      await gw.stop();
      exit(0);
    });
  } catch (_) {
    // SIGTERM poate lipsi pe unele platforme.
  }

  await Completer<void>().future;
}
