import 'package:flutter/material.dart';

import 'package:defib_core/models.dart';

import '../app_state.dart';

/// Grafic ECG derulant (ultimele [secondsVisible] secunde), stil monitor.
class EcgChart extends StatelessWidget {
  const EcgChart({
    super.key,
    required this.state,
    this.secondsVisible = 5,
    this.verticalRangeMv = 2.5,
  });

  final AppState state;
  final double secondsVisible;
  final double verticalRangeMv;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: state.ecgTick,
      builder: (context, _, __) => CustomPaint(
        painter: _EcgPainter(
          samples: state.ecg.lastN((secondsVisible * 250).round()),
          rangeMv: verticalRangeMv,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  final List<double> samples;
  final double rangeMv;

  _EcgPainter({required this.samples, required this.rangeMv});

  @override
  void paint(Canvas canvas, Size size) {
    // Fundal.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.black);

    // Grilă: linii fine la 0.5 s orizontal și 0.5 mV vertical.
    final grid = Paint()
      ..color = const Color(0xFF003B00)
      ..strokeWidth = 1;
    final w = size.width;
    final h = size.height;
    final xStep = w / (secondsVisibleX * 2);
    for (double x = 0; x < w; x += xStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    final yStep = h / (rangeMv * 2); // 1 mV => rangeMv*2 divizii
    for (double y = h / 2 % yStep; y < h; y += yStep) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    // Trasarea ECG.
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFF00FF66)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final n = samples.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1) * w;
      final y = h / 2 - (samples[i].clamp(-rangeMv, rangeMv) / rangeMv) * (h / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  // 10 divizii orizontale = 1 secundă? Nu: aici 1 divizie = 0.5 s.
  static const double secondsVisibleX = 10;

  @override
  bool shouldRepaint(_EcgPainter old) => true;
}
