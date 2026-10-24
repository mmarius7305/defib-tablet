import 'package:flutter/material.dart';

import 'package:defib_core/connection.dart';
import 'package:defib_core/models.dart';
import 'package:defib_core/simulator.dart';

import '../app_state.dart';
import 'connect_screen.dart' show InheritedAppState;
import 'widgets/ecg_chart.dart';

/// Monitorul live: ECG derulant + semne vitale + jurnal de evenimente.
///
/// Arată la fel indiferent de driver (simulator, Corpuls sau alt aparat),
/// pentru că ascultă doar interfața DefibrillatorDriver.
class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = InheritedAppState.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final v = state.latestVitals;
        final isSim = state.driver is SimulatorDriver;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(state.statusMessage),
            actions: [
              IconButton(
                icon: const Icon(Icons.power_settings_new),
                tooltip: 'Deconectare',
                onPressed: () async {
                  await state.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // ECG: ~35% din ecran.
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: EcgChart(state: state, secondsVisible: 6),
                  ),
                ),
                // Semne vitale: 4 dale mari.
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      _VitalTile(
                        label: 'FC',
                        value: v?.heartRate?.round().toString(),
                        unit: 'bpm',
                        color: const Color(0xFF00FF66),
                      ),
                      _VitalTile(
                        label: 'SpO₂',
                        value: v?.spo2?.round().toString(),
                        unit: '%',
                        color: Colors.cyan,
                      ),
                      _VitalTile(
                        label: 'EtCO₂',
                        value: v?.etco2?.round().toString(),
                        unit: 'mmHg',
                        color: Colors.amber,
                      ),
                      _VitalTile(
                        label: 'NIBP',
                        value: v?.nibp != null
                            ? '${v!.nibp!.systolic}/${v.nibp!.diastolic}'
                            : null,
                        unit: 'mmHg',
                        color: Colors.deepOrange,
                      ),
                    ],
                  ),
                ),
                // Panou simulator: doar când driverul e simulatorul.
                if (isSim)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final r in SimRhythm.values)
                          ActionChip(
                            label: Text(_rhythmLabel(r)),
                            onPressed: () => state.simulateRhythm(r),
                          ),
                        ActionChip(
                          label: const Text('ȘOC 150J'),
                          onPressed: () => state.simulateShock(),
                        ),
                      ],
                    ),
                  ),
                // Jurnal evenimente.
                Expanded(
                  flex: 2,
                  child: ListView.builder(
                    itemCount: state.events.length,
                    padding: const EdgeInsets.all(6),
                    itemBuilder: (context, i) {
                      final e = state.events[i];
                      final ts = e.timestamp.toIso8601String().substring(11, 19);
                      final energy = e.energyJoules != null ? ' ${e.energyJoules}J' : '';
                      return Text(
                        '$ts  ${_eventLabel(e)}$energy',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _rhythmLabel(SimRhythm r) => switch (r) {
        SimRhythm.sinus => 'Sinus',
        SimRhythm.vtach => 'VT',
        SimRhythm.vfib => 'VF',
        SimRhythm.asystole => 'Asistolie',
      };

  static String _eventLabel(DefibEvent e) => switch (e.type) {
        DefibEventType.rhythmAnalysis => 'Analiză ritm',
        DefibEventType.shockAdvised => 'Șoc recomandat',
        DefibEventType.shockDelivered => 'ȘOC ADMINISTRAT',
        DefibEventType.chargeStarted => 'Încărcare',
        DefibEventType.pacingStarted => 'Pacing pornit',
        DefibEventType.pacingStopped => 'Pacing oprit',
        DefibEventType.electrodeWarning => 'Avertizare electrozi',
        DefibEventType.deviceSelfTest => 'Auto-test',
        DefibEventType.other => 'Eveniment',
      };
}

/// O dală mare de semn vital, stil monitor de teren.
class _VitalTile extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;
  final Color color;

  const _VitalTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black87,
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(color: color, fontSize: 18)),
              Text(
                value ?? '--',
                style: TextStyle(
                    color: value == null ? Colors.white24 : color,
                    fontSize: 44,
                    fontWeight: FontWeight.bold),
              ),
              Text(unit, style: const TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}
