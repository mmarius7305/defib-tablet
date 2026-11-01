/// Modele de date comune tuturor driverelor de dispozitive medicale.
///
/// Aceste clase nu depind de nicio platformă (iOS / Android / Windows CE),
/// ca să poată fi refolosite și testate identic peste tot.
library;

/// Starea pupilelor (cadru 0x07 / 17A).
enum PupilsStatus { normal, midriatice, miotice, anisocorie, nereactive }

/// O măsurătoare agregată de semne vitale, preluată de la monitor.
class VitalsSample {
  final DateTime timestamp;
  final double? heartRate; // bpm
  final double? spo2; // %
  final double? etco2; // mmHg
  final double? temperature; // °C
  final NibpReading? nibp;
  final double? respiratoryRate; // /min
  final double? glucose; // mg/dL
  final int? gcs;
  final PupilsStatus? pupils;

  const VitalsSample({
    required this.timestamp,
    this.heartRate,
    this.spo2,
    this.etco2,
    this.temperature,
    this.nibp,
    this.respiratoryRate,
    this.glucose,
    this.gcs,
    this.pupils,
  });

  @override
  String toString() =>
      'VitalsSample(${timestamp.toIso8601String()} HR=${heartRate ?? "-"} '
      'SpO2=${spo2 ?? "-"} EtCO2=${etco2 ?? "-"})';
}

/// O măsurătoare de tensiune arterială (non-invazivă).
class NibpReading {
  final int systolic;
  final int diastolic;
  final int mean;
  final DateTime takenAt;

  const NibpReading({
    required this.systolic,
    required this.diastolic,
    required this.mean,
    required this.takenAt,
  });
}

/// Tipurile de evenimente pe care le poate raporta un defibrilator/monitor.
enum DefibEventType {
  rhythmAnalysis,
  shockAdvised,
  shockDelivered,
  chargeStarted,
  pacingStarted,
  pacingStopped,
  electrodeWarning,
  deviceSelfTest,
  other,
}

/// Un eveniment petrecut pe aparat (șoc, analiză de ritm, pacing, alarmă).
class DefibEvent {
  final DateTime timestamp;
  final DefibEventType type;
  final int? energyJoules;
  final String? detail;
  final bool successful;

  const DefibEvent({
    required this.timestamp,
    required this.type,
    this.energyJoules,
    this.detail,
    this.successful = true,
  });

  @override
  String toString() =>
      'DefibEvent(${timestamp.toIso8601String()} $type'
      '${energyJoules != null ? " ${energyJoules}J" : ""})';
}

/// Buffer inelar pentru un canal ECG, cu rată de eșantionare fixă.
///
/// Se scrie continuu (la fiecare mostre primită de la aparat) și UI-ul
/// citește doar fereastra recentă pentru desenare.
class EcgWaveform {
  final int sampleRateHz;
  final int capacitySamples;

  final List<double> _buf;
  int _writeIdx = 0;
  int _count = 0;

  EcgWaveform({
    required this.sampleRateHz,
    this.capacitySamples = 250 * 30, // 30 de secunde la 250 Hz
  }) : _buf = List<double>.filled(capacitySamples, 0.0, growable: false);

  /// Numărul de mostre valabile (maxim [capacitySamples]).
  int get length => _count;

  /// Adaugă o mostră în milivolți.
  void push(double millivolts) {
    _buf[_writeIdx] = millivolts;
    _writeIdx = (_writeIdx + 1) % capacitySamples;
    if (_count < capacitySamples) _count++;
  }

  /// Adaugă mai multe mostre.
  void pushAll(Iterable<double> millivolts) {
    for (final v in millivolts) {
      push(v);
    }
  }

  /// Ultimele [n] mostre, în ordine cronologică (cea mai veche prima).
  /// Dacă există mai puține decât [n], le returnează pe toate.
  List<double> lastN(int n) {
    n = n > _count ? _count : n;
    final out = List<double>.filled(n, 0.0, growable: false);
    final start = (_writeIdx - n + capacitySamples) % capacitySamples;
    for (var i = 0; i < n; i++) {
      out[i] = _buf[(start + i) % capacitySamples];
    }
    return out;
  }

  /// Valoarea de la poziția [i] a ferestrei valabile (0 = cea mai veche).
  double at(int i) => _buf[(_writeIdx - _count + i + capacitySamples * 2) % capacitySamples];

  void clear() {
    _writeIdx = 0;
    _count = 0;
  }
}
