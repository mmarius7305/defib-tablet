/// Comenzi de telecomandă SAJLink (cadru tip [SajFrameType.command] = 0x04).
///
/// Tableta / gateway-ul trimite aceste comenzi către aparat sau simulator.
/// Toate valorile sunt sintetice în laborator — nu reprezintă un dispozitiv
/// medical certificat.
library;

import 'dart:typed_data';

import 'frames.dart';

/// Ritmurile pe care le poate forța telecomanda (simulator / lab).
enum SimRhythm { sinus, vtach, vfib, asystole }

/// Opcode-uri din payload-ul cadrului de comandă (primul octet).
class SajCommand {
  static const int setRhythm = 1;
  static const int deliverShock = 2;
  static const int selfTest = 3;
}

/// Interfață pentru driverele care acceptă telecomandă (ritm / șoc / auto-test).
abstract class RemoteControllable {
  /// `true` când driverul poate trimite comenzi pe transportul curent.
  bool get supportsRemoteControl;

  Future<void> setRhythm(SimRhythm rhythm);

  Future<void> deliverShock({int joules = 150});

  Future<void> runSelfTest();
}

Uint8List _cmdPayload(List<int> bytes) =>
    SajLinkCodec.encode(SajFrame(SajFrameType.command, bytes));

/// Codifică un cadru SAJLink de comandă.
Uint8List encodeCommand(int opcode, [List<int> args = const []]) =>
    _cmdPayload([opcode, ...args]);

/// Cadru: schimbă ritmul simulatorului.
Uint8List encodeSetRhythm(SimRhythm rhythm) =>
    encodeCommand(SajCommand.setRhythm, [rhythm.index]);

/// Cadru: administrează un șoc de test (energie little-endian u16).
Uint8List encodeDeliverShock({int joules = 150}) => _cmdPayload([
      SajCommand.deliverShock,
      joules & 0xFF,
      (joules >> 8) & 0xFF,
    ]);

/// Cadru: cere un auto-test.
Uint8List encodeSelfTest() => encodeCommand(SajCommand.selfTest);
