# 17E — Ecran tabletă: timpi de misiune și navigare (B44-O5) v0.03

| | |
|---|---|
| **Document** | 17E_B44_ECRAN_TABLETA_TIMPI_SI_GPS_v0.03.md |
| **Autor** | Operator B44 (zona telemetrie) |
| **Stare** | Implementat în `defib-tablet` (ramură remote-control) |
| **Referințe** | 17B (gateway REST/WS), ordin B44-O5 |

## 1. Scop

Ecranul de echipaj pe tabletă (Flutter) pentru:

1. Starea legăturii cu gateway-ul: **ONLINE** / **STORE-AND-FORWARD** / **OFFLINE**
2. Butoane de timp mapate pe cheile 17B / `PK_TIMPI`
3. Anti-dublu-click (800 ms) și coadă locală offline
4. Buton **NAVIGARE** către `geo:` / OsmAnd / Organic Maps
5. URL gateway configurabil — **zero IP-uri de producție hardcodate**

## 2. Mapare butoane → chei

| Buton UI | Cheie 17B |
|---|---|
| PLECARE | `plecare_garaj` |
| SOSIRE | `sosire_adresa` |
| PLECARE CAZ | `plecare_adresa` |
| SPITAL | `sosire_spital` |
| PREDARE | `predare_pacient` |
| LIBER | `incheiere_misiune` |

Valoarea trimisă: `HH:mm` (ora locală). MULTI-ZI e tratat de gateway (17B §4.3).

## 3. Fișiere

| Fișier | Rol |
|---|---|
| `core/lib/mission.dart` | Chei, coadă offline, client HTTP gateway |
| `lib/net/gateway_session.dart` | Sesiune UI: poll, flush, stări link |
| `lib/ui/crew_screen.dart` | Ecranul echipaj |
| `core/lib/remote_control.dart` | Comenzi SAJLink 0x04 (telecomandă aparat) |
| `core/lib/tcp_transport.dart` + `sajlink_driver.dart` | Client TCP SAJLink |
| `core/tool/sim_server.dart` | Simulator remote pe `:45678` |

## 4. Telecomandă aparat (complement O5)

Pe lângă timpii de misiune, tableta poate telecomanda un simulator/aparat SAJLink:

- Cadre `0x04`: set rhythm / deliver shock / self-test
- Transport TCP (`TcpTransport`) sau in-process (`SimulatorTransport`)
- Panoul de pe `MonitorScreen` apare pentru orice `RemoteControllable`

## 5. Teste

```bash
cd core && dart pub get && dart test
dart run tool/verify.dart
```

Acoperă codec, ECG, telecomandă TCP loopback, coada offline anti-dublu-click.

## 6. Constrângeri

- Date sintetice / operaționale (ore) — Directiva ZERO/1
- Fără secrete, tokeni sau IP-uri de producție în sursă
- Gateway-ul rămâne pe LAN/VPN (17B)
