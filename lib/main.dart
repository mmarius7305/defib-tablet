import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/connect_screen.dart' show InheritedAppState, ConnectScreen;

/// DefibTablet — monitor live de date de la defibrilator.
///
/// Structură:
///   core/            nucleul pur Dart (drivere, codec, model ECG) — testat.
///   lib/ble/         transport Bluetooth LE (flutter_blue_plus).
///   lib/ui/          ecrane: conectare + monitor live.
///
/// Driverul Corpuls 3 e schelet până la documentația oficială de parteneriat;
/// aplicația rulează complet cu simulatorul integrat.
void main() {
  final appState = AppState();
  runApp(
    InheritedAppState(
      notifier: appState,
      child: const DefibTabletApp(),
    ),
  );
}

class DefibTabletApp extends StatelessWidget {
  const DefibTabletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DefibTablet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A86B),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A86B),
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
