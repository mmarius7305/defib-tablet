/// Codec de cadre „SAJLink" — protocolul de testare/dezvoltare folosit de
/// simulatorul integrat și de viitoarele instrumente de lab.
///
/// ATENȚIE: SAJLink NU este protocolul Corpuls 3 sau al oricărui aparat real.
/// Driverul unui aparat real primește specificația oficială de la producător
/// (ex. prin programul de parteneri GS Elektromedizinische / corpuls.connect)
/// și implementează codec-ul respectiv în locul acestuia. Formatul de aici
/// există ca să poată fi dezvoltată și testată toată aplicația fără hardware.
///
/// Format de cadru:
///   magic  : 4 octeți  "SJL1"
///   tip    : 1 octet   (vezi [SajFrameType])
///   lungime: 2 octeți  little-endian (dimensiunea payload-ului)
///   payload: `lungime` octeți
///   crc16  : 2 octeți  little-endian, CRC-16/CCITT (init 0xFFFF, poly 0x1021)
library;

import 'dart:typed_data';

/// Tipuri de cadre SAJLink.
class SajFrameType {
  static const int vitals = 1;
  static const int ecgBatch = 2;
  static const int event = 3;
  static const int command = 4;
  static const int ack = 5;
  static const int error = 6;
}

class SajFrame {
  final int type;
  final Uint8List payload;

  /// [payload] poate fi orice listă de octeți; e copiată în `Uint8List`.
  SajFrame(int type, List<int> payload)
      : type = type,
        payload = payload is Uint8List ? payload : Uint8List.fromList(payload);

  @override
  String toString() => 'SajFrame(type=$type, len=${payload.length})';
}

/// Codifică și decodifică cadre SAJLink dintr-un flux de octeți.
class SajLinkCodec {
  static const _magic = [0x53, 0x4A, 0x4C, 0x31]; // "SJL1"

  final List<int> _buf = [];

  /// CRC-16/CCITT (init 0xFFFF, poly 0x1021).
  static int crc16(List<int> data, [int start = 0, int? end]) {
    end ??= data.length;
    var crc = 0xFFFF;
    for (var i = start; i < end; i++) {
      crc ^= data[i] << 8;
      for (var b = 0; b < 8; b++) {
        crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  /// Codifică un cadru complet (magic + tip + lungime + payload + CRC).
  static Uint8List encode(SajFrame frame) {
    if (frame.payload.length > 0xFFFF) {
      throw ArgumentError('Payload prea mare pentru SAJLink: ${frame.payload.length}');
    }
    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(frame.type);
    out.addByte(frame.payload.length & 0xFF);
    out.addByte((frame.payload.length >> 8) & 0xFF);
    out.add(frame.payload);
    final flat = out.toBytes();
    // CRC calculat peste tip + lungime + payload.
    final crc = crc16(flat, 3, 7 + frame.payload.length);
    out.addByte(crc & 0xFF);
    out.addByte((crc >> 8) & 0xFF);
    return out.toBytes();
  }

  /// Alimentează codec-ul cu octeți primiți (în orice bucăți).
  void feed(List<int> bytes) => _buf.addAll(bytes);

  /// Încearcă să extragă următorul cadru complet din buffer.
  ///
  /// Returnează `null` dacă bufferul nu conține (încă) un cadru complet.
  /// Un cadru cu CRC greșit este aruncat în întregime și căutarea reia de la
  /// următorul magic, ca transportul să rămână rezilient la zgomot.
  SajFrame? decodeNext() {
    while (true) {
      final magicIdx = _indexOfMagic();
      if (magicIdx < 0) {
        // Păstrează ultimii 3 octeți, pot fi început de magic.
        _trimToSuffix(_buf.length > 3 ? 3 : _buf.length);
        return null;
      }
      if (magicIdx > 0) _buf.removeRange(0, magicIdx);

      if (_buf.length < 9) return null; // header(7) + crc(2) minim.

      final len = _buf[5] | (_buf[6] << 8);
      final total = 7 + len + 2;
      if (_buf.length < total) return null;

      final expectedCrc = _buf[7 + len] | (_buf[7 + len + 1] << 8);
      final actualCrc = crc16(_buf, 3, 7 + len);
      if (expectedCrc != actualCrc) {
        // Cadru corupt: aruncă magic-ul și reia căutarea.
        _buf.removeRange(0, 4);
        continue;
      }
      final type = _buf[4];
      final payload = Uint8List.fromList(_buf.sublist(7, 7 + len));
      _buf.removeRange(0, total);
      return SajFrame(type, payload);
    }
  }

  int _indexOfMagic() {
    for (var i = 0; i + 3 < _buf.length; i++) {
      if (_buf[i] == _magic[0] &&
          _buf[i + 1] == _magic[1] &&
          _buf[i + 2] == _magic[2] &&
          _buf[i + 3] == _magic[3]) {
        return i;
      }
    }
    return -1;
  }

  void _trimToSuffix(int keep) {
    if (_buf.length > keep) {
      _buf.removeRange(0, _buf.length - keep);
    }
  }
}
