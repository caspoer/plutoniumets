import 'package:flutter/material.dart';

import '../models/scan_point.dart';

class RssiChart extends StatelessWidget {
  const RssiChart({required this.points});
  final List<ScanPoint> points;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: RssiChartPainter(points),
      );
}

class RssiChartPainter extends CustomPainter {
  RssiChartPainter(this.points);
  final List<ScanPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 80 || size.height < 60) return;
    final plot = Rect.fromLTWH(42, 12, size.width - 54, size.height - 38);
    final values = points.map((point) => point.rssiDb).toList();
    var minValue = values.reduce((a, b) => a < b ? a : b);
    var maxValue = values.reduce((a, b) => a > b ? a : b);
    if (minValue == maxValue) {
      minValue -= 1;
      maxValue += 1;
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.35)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? plot.center.dx
          : plot.left + plot.width * i / (points.length - 1);
      final y = plot.bottom -
          ((points[i].rssiDb - minValue) / (maxValue - minValue)) * plot.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.indigo
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    _drawLabel(canvas, '${maxValue.toStringAsFixed(1)} dB',
        Offset(0, plot.top - 6));
    _drawLabel(canvas, '${minValue.toStringAsFixed(1)} dB',
        Offset(0, plot.bottom - 12));
    _drawLabel(canvas, '${points.first.frequencyMHz.toStringAsFixed(1)} MHz',
        Offset(plot.left, plot.bottom + 6));
    _drawLabel(canvas, '${points.last.frequencyMHz.toStringAsFixed(1)} MHz',
        Offset(plot.right - 75, plot.bottom + 6));
  }

  void _drawLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant RssiChartPainter oldDelegate) => true;
}

