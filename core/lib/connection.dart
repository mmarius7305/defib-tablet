/// Interfețele care despart „transportul de octeți" de „interpretarea datelor".
///
/// Arhitectura: [ByteTransport] duce octeți (Bluetooth, USB, simulator, socket),
/// iar un [DefibrillatorDriver] transformă octeții în [VitalsSample], ECG și
/// evenimente. UI-ul vede doar drivere, niciodată detaliile de transport.
library;

import 'models.dart';

/// Conexiune de octeți către un dispozitiv extern.
abstract class ByteTransport {
  /// Flux de pachete de octeți primite de la dispozitiv.
  Stream<List<int>> get incoming;

  /// Trimite octeți către dispozitiv.
  Future<void> send(List<int> data);

  /// Închide conexiunea.
  Future<void> close();

  /// `true` cât timp conexiunea e deschisă.
  bool get isOpen;
}

/// Starea unui driver.
enum DriverState { disconnected, connecting, connected, error }

/// Contractul comun pentru orice defibrilator / monitor de semne vitale.
abstract class DefibrillatorDriver {
  /// Numele dispozitivului (ex. "Corpuls 3", "Simulator", "ZOLL X Series").
  String get name;

  DriverState get state;

  /// Rata de eșantionare a canalului ECG, în Hz.
  int get ecgSampleRateHz;

  /// Semne vitale agregate, emise periodic (recomandat: la 1 s).
  Stream<VitalsSample> get vitals;

  /// Mostre ECG brute, în milivolți, emise pe măsură ce sosesc.
  Stream<double> get ecgMillivolts;

  /// Evenimente de la aparat: șocuri, analize de ritm, alarme, pacing.
  Stream<DefibEvent> get events;

  /// Conectează driverul peste un transport dat.
  Future<void> connect(ByteTransport transport);

  /// Deconectează driverul și eliberează resursele.
  Future<void> disconnect();
}
