import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:defib_core/frames.dart';

void main() {
  test('roundtrip: encode -> decode reproduce cadrul', () {
    final payload = List<int>.generate(37, (i) => (i * 7) & 0xFF);
    final frame = SajFrame(SajFrameType.vitals, payload);
    final codec = SajLinkCodec()..feed(SajLinkCodec.encode(frame));
    final decoded = codec.decodeNext();
    expect(decoded, isNotNull);
    expect(decoded!.type, SajFrameType.vitals);
    expect(decoded.payload, payload);
  });

  test('alimentare cu câte un octet decodifică cadrele corect', () {
    final f1 = SajFrame(SajFrameType.ecgBatch, [1, 2, 3, 4, 5]);
    final f2 = SajFrame(SajFrameType.event, [9, 9]);
    final bytes = [...SajLinkCodec.encode(f1), ...SajLinkCodec.encode(f2)];

    final codec = SajLinkCodec();
    final decoded = <SajFrame>[];
    for (final b in bytes) {
      codec.feed([b]);
      while (true) {
        final f = codec.decodeNext();
        if (f == null) break;
        decoded.add(f);
      }
    }
    expect(decoded.length, 2);
    expect(decoded[0].type, SajFrameType.ecgBatch);
    expect(decoded[1].type, SajFrameType.event);
  });

  test('cadru cu CRC corupt este respins, următorul valid e decodificat', () {
    final good = SajFrame(SajFrameType.command, [1, 2, 3]);
    final raw = SajLinkCodec.encode(good).toList();
    raw[8] ^= 0xFF; // corupe un octet din payload

    final good2 = SajFrame(SajFrameType.ack, [77]);
    final codec = SajLinkCodec()
      ..feed(raw)
      ..feed(SajLinkCodec.encode(good2));

    // Cadrul corupt e aruncat tăcut; decodificarea reia la următorul valid.
    final next = codec.decodeNext();
    expect(next, isNotNull);
    expect(next!.type, SajFrameType.ack);
    expect(next.payload, [77]);
    expect(codec.decodeNext(), isNull);
  });

  test('zgomot înainte de magic este ignorat', () {
    final frame = SajFrame(SajFrameType.error, [0xAA]);
    final codec = SajLinkCodec()
      ..feed([0x00, 0x12, 0x34, 0x53]) // zgomot (ultimul octet = S)
      ..feed(SajLinkCodec.encode(frame));
    final decoded = codec.decodeNext();
    expect(decoded, isNotNull);
    expect(decoded!.payload, [0xAA]);
  });

  test('payload mare (500 octeți) trece prin codec', () {
    final rnd = math.Random(3);
    final payload =
        List<int>.generate(500, (_) => rnd.nextInt(256));
    final codec = SajLinkCodec()..feed(SajLinkCodec.encode(SajFrame(2, payload)));
    expect(codec.decodeNext()!.payload, payload);
  });
}
