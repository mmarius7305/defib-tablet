# DefibTablet — Windows CE (schelet)

## De ce un cod separat

Flutter nu rulează pe Windows CE (platformă întreruptă, ARMv4/ARMv5,
.NET Compact Framework 3.5). Pentru tabletele CE folosite pe ambulanțe
trebuie o aplicație nativă C# care reimplementează aceleași două ecrane
(conectare + monitor). Nucleul logic (codec SAJLink, model ECG) este
reprodus în C# în `DefibCore.cs`, ca rezultatul să fie identic cu cel
verificat în Dart.

## Instrumente necesare

- Visual Studio 2008 Professional (singura versiune cu suport .NET CF 3.5)
- Windows CE SDK-ul specific tabletei (de la producător)
- Opțional: InTheHand.Net (Bluetooth clasic / SPP) — BLE nu există pe
  majoritatea build-urilor CE.

## Limitări importante pe CE

1. **Bluetooth**: CE 6.0/7.0 are doar stack-ul Microsoft cu profiluri
   clasice (SPP = port serial). **BLE nu este suportat nativ.** Dacă
   defibrilatorul comunică doar BLE, tableta CE trebuie conectată prin:
   - adaptor serial/USB, sau
   - Wi-Fi (socket TCP), sau
   - un mic gateway BLE→SPP/Wi-Fi montat pe ambulanță.
2. **Randare**: GDI+ pe CE e lent; ECG-ul se desenează cu dublu buffering
   pe un `Panel` cu maxim ~30 fps.
3. **EOL**: CE este întrerupt de mult; pentru achiziții noi recomandăm
   tabletă Android rugged cu Bluetooth LE, care rulează aplicația Flutter
   nealterată.

## Fișiere

- `DefibCore.cs` — nucleul C# (codec SAJLink, buffer ECG), portabil.
- `MainForm.cs` — ecranul monitor cu desen ECG și dale de semne vitale.

Build: proiect „Smart Device” în VS2008, target dispozitiv CE 6.0+,
orice rezoluție ≥ 800x480 (design pe 800x480, ecran complet).
