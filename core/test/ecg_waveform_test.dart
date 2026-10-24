import 'package:test/test.dart';

import 'package:defib_core/models.dart';

void main() {
  test('păstrează ordinea cronologică a mostrelor', () {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 8);
    w.pushAll([1, 2, 3]);
    expect(w.lastN(10), [1, 2, 3]);
    expect(w.length, 3);
  });

  test('suprascrie circular: cele mai vechi mostre dispar', () {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 4);
    w.pushAll([1, 2, 3, 4, 5, 6]);
    expect(w.length, 4);
    expect(w.lastN(4), [3, 4, 5, 6]);
  });

  test('lastN(n) cu n > lungime returnează tot ce există', () {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 100);
    w.pushAll([1, 2]);
    expect(w.lastN(50), [1, 2]);
  });

  test('at(i) citește corect după mai multe rotiri', () {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 3);
    w.pushAll([10, 20, 30, 40, 50]); // fereastra = 30, 40, 50
    expect(w.at(0), 30);
    expect(w.at(1), 40);
    expect(w.at(2), 50);
  });

  test('clear resetează fereastra', () {
    final w = EcgWaveform(sampleRateHz: 250, capacitySamples: 10);
    w.pushAll([1, 2, 3]);
    w.clear();
    expect(w.length, 0);
    expect(w.lastN(10), isEmpty);
  });
}
