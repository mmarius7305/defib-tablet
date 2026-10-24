import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:defib_core/connection.dart';

/// Transport Bluetooth LE construit peste flutter_blue_plus.
///
/// Se conectează la dispozitiv, abonează la notificările caracteristicii RX
/// și scrie comenzile în caracteristica TX. UUID-urile vin din configurația
/// driverului (de ex. [CorpulsDriver] când documentația oficială e disponibilă,
/// sau alt aparat configurat similar).
class BleTransport implements ByteTransport {
  final BluetoothDevice device;
  final Guid serviceUuid;
  final Guid rxCharacteristicUuid; // dispozitiv -> tabletă
  final Guid txCharacteristicUuid; // tabletă -> dispozitiv

  final _incoming = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _notifySub;
  BluetoothCharacteristic? _txChar;
  bool _open = false;

  BleTransport({
    required this.device,
    required this.serviceUuid,
    required this.rxCharacteristicUuid,
    required this.txCharacteristicUuid,
  });

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  Future<void> connect() async {
    await device.connect();
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == serviceUuid,
      orElse: () => throw StateError('Serviciul $serviceUuid nu a fost găsit.'),
    );
    final rx = service.characteristics.firstWhere(
      (c) => c.uuid == rxCharacteristicUuid,
      orElse: () => throw StateError('Caracteristica RX nu a fost găsită.'),
    );
    _txChar = service.characteristics.firstWhere(
      (c) => c.uuid == txCharacteristicUuid,
      orElse: () => throw StateError('Caracteristica TX nu a fost găsită.'),
    );
    await rx.setNotifyValue(true);
    _notifySub = rx.lastValueStream.listen(_incoming.add);
    _open = true;
  }

  @override
  Future<void> send(List<int> data) async {
    if (!_open) throw StateError('Transportul BLE nu este conectat.');
    await _txChar!.write(data, withoutResponse: false);
  }

  @override
  Future<void> close() async {
    _open = false;
    await _notifySub?.cancel();
    await _incoming.close();
    try {
      await device.disconnect();
    } catch (_) {
      // deconectare deja făcută de partea cealaltă.
    }
  }
}
