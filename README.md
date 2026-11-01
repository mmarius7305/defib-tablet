# DefibTablet

Aplicație tabletă care se conectează la un monitor-defibrilator, preia
datele (ECG + semne vitale + evenimente) și le afișează live pe ecran.

- **iOS / Android**: aplicație Flutter (`lib/`).
- **Windows CE**: aplicație separată C# .NET CF 3.5 (`wince/`), același
  codec și același ecran de monitor.
- **Nucleul comun** (`core/`, Dart pur, portat și în C#): drivere,
  codec de cadre, buffer ECG, telecomandă TCP, timpi misiune.
  **22/22 teste** + **17/17 verificări** standalone (vezi mai jos).

## Structură

```
defib-tablet/
├── core/                     nucleul Dart pur (rulează identic pe toate platformele)
│   ├── lib/
│   │   ├── models.dart       VitalsSample, DefibEvent, EcgWaveform (buffer inelar)
│   │   ├── connection.dart   ByteTransport, DefibrillatorDriver (contractele comune)
│   │   ├── frames.dart       codec SAJLink (protocol de dezvoltare/test)
│   │   ├── simulator.dart    simulator + driver simulator (ECG sintetic real-timp)
│   │   └── corpuls_driver.dart  schelet Corpuls 3 (așteaptă documentația oficială)
│   ├── test/                 teste (rulate cu `dart test`)
│   └── tool/verify.dart      verificare standalone (`dart run tool/verify.dart`)
├── lib/                      aplicația Flutter (iOS/Android)
│   ├── main.dart             intrare + temă
│   ├── app_state.dart        starea aplicației (leagă driverele de UI)
│   ├── ble/ble_transport.dart transport Bluetooth LE (flutter_blue_plus)
│   └── ui/                   ecrane: conectare + monitor live (ECG + vitals)
└── wince/                    aplicația Windows CE (C# .NET CF 3.5)
    ├── DefibCore.cs          port C# al codec-ului și modelului ECG
    ├── MainForm.cs           ecranul monitor cu desen ECG
    └── README.md             cerințe VS2008 + limitările platformei CE
```

## Arhitectura

```
[Corpuls 3]   [alt aparat]   [simulator]
     │              │             │
     └── DriverCorpuls ── DriverZoll ── SimulatorDriver
                  (toate implementează DefibrillatorDriver)
                          │
                   ByteTransport  (BLE / USB / Wi-Fi / in-process)
                          │
                    AppState  →  UI (monitor live)
```

Fiecare aparat are un driver; UI-ul nu știe niciodată cu ce e conectat.
Adăugarea unui aparat nou = un fișier driver nou, zero schimbări în UI.

## Rulare (iOS / Android)

```bash
flutter pub get
flutter run          # cu dispozitiv/emulator conectat
flutter build apk    # Android
flutter build ios    # iOS (necesită macOS + Xcode)
```

La pornire: ecranul de conectare oferă **Simulator integrat** (rulează
integral, fără hardware — ECG la 250 Hz, FC/SpO₂/EtCO₂, comenzi de ritm
și șoc), **Telecomandă TCP** (client SAJLink către `sim_server` pe portul
45678 — ritm / șoc / auto-test pe LAN), **Echipaj — timpi misiune**
(butoane PLECARE…LIBER pe gateway, ONLINE / STORE-AND-FORWARD, vitale live, navigare)
și **Bluetooth LE** (scanare + transport generic).

```bash
# pe PC-ul din ambulanță / lab (simulator remote + gateway LAN):
cd core && dart run tool/sim_server.dart --port 45678
cd core && dart run tool/gateway.dart --source 127.0.0.1:45678 --http 8089 --store ./gateway_store
```

## Verificarea nucleului

```bash
cd core
dart pub get
dart test                    # 22 teste (telecomandă TCP + gateway 17B)
# sau, în medii fără runner:
dart run tool/verify.dart    # 17 verificări
```

Acoperă: codec-ul SAJLink (roundtrip, octet-cu-octet, CRC corupt, zgomot,
payloaduri mari), bufferul ECG (ordine, circularitate, clear),
simulatorul (bătăi 72/180 bpm, vitale, șocuri, schimbare ritm),
telecomanda TCP loopback (șoc 200 J, rhythmAnalysis), coada offline
anti-dublu-click și gateway-ul 17B (REST, MULTI-ZI, WS, SSE, persistare).

## Integrarea reală Corpuls 3 — pașii rămași

Driverul `core/lib/corpuls_driver.dart` are interfața completă și TODO-uri
marcate exact unde se inserează protocolul real. Ai nevoie de:

1. **Acces la documentația/parteneriatul GS Elektromedizinische**
   (programul de parteneri / corpuls.connect) — singura sursă legală a
   protocolului; Bluetooth-ul Corpuls 3 nu este public.
2. Cu documentația: completezi UUID-urile GATT și parsarea cadrelor în
   `CorpulsDriver` (structura e identică cu `SimulatorDriver`).
3. Alternativ, cloud: corpuls.connect preia datele de sesiune din cloud
   cu API oficial — atunci transportul e HTTPS, nu BLE, și driverul
   rămâne singurul fișier modificat.

## Windows CE

Vezi `wince/README.md`. Pe scurt: cod separat (CE nu rulează Flutter),
aceleași cadre SAJLink portate în C#, conectare prin SPP/serial sau Wi-Fi
(CE nu are BLE), VS2008 + SDK-ul tabletei. Aceleași TODO-uri pentru
protocolul Corpuls.

## Avertisment

Prototip de dezvoltare. **Nu este dispozitiv medical certificat** și nu
se folosește pentru decizii clinice. Utilizarea în ambulator real
presupune evaluare MDR/ANMDM, contract cu producătorul aparatului și
teste de securitate. Datele pacientului nu se transmit nicăieri în
această versiune; rămân local pe tabletă.
