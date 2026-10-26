import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Line icons that the Lucide set does not have, drawn to match its 24-unit,
/// round-capped stroke style.
class DomeIcon extends StatelessWidget {
  const DomeIcon({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LinePainter(color, _dome));

  static void _dome(Canvas canvas, Paint p, Paint fill) {
    final path = Path()
      ..moveTo(12, 4.2)
      ..cubicTo(12, 4.2, 9.2, 6.6, 7.4, 8.8)
      ..cubicTo(6, 10.4, 5.6, 11.8, 5.6, 13.4)
      ..lineTo(5.6, 20.5)
      ..lineTo(18.4, 20.5)
      ..lineTo(18.4, 13.4)
      ..cubicTo(18.4, 11.8, 18, 10.4, 16.6, 8.8)
      ..cubicTo(14.8, 6.6, 12, 4.2, 12, 4.2)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(const Offset(12, 1.6), const Offset(12, 4.2), p);
    canvas.drawLine(const Offset(3.2, 20.5), const Offset(20.8, 20.5), p);
    // brick courses across the base
    canvas.drawLine(const Offset(5.6, 16.6), const Offset(18.4, 16.6), p);
  }
}

/// An oud-style lute with a small sparkle, for the Instrumental card.
class OudIcon extends StatelessWidget {
  const OudIcon({super.key, required this.color, this.size = 22});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LinePainter(color, _oud));

  static void _oud(Canvas canvas, Paint p, Paint fill) {
    canvas.drawCircle(const Offset(9.2, 15.2), 5.8, p);
    final diamond = Path()
      ..moveTo(9.2, 12.9)
      ..lineTo(11.5, 15.2)
      ..lineTo(9.2, 17.5)
      ..lineTo(6.9, 15.2)
      ..close();
    canvas.drawPath(diamond, p);
    canvas.drawLine(const Offset(13.3, 11.1), const Offset(19.2, 5.2), p);
    canvas.drawLine(const Offset(17.4, 3.6), const Offset(20.8, 7.0), p);
    _sparkle(canvas, fill, const Offset(5.2, 5.6), 2.7);
    _sparkle(canvas, fill, const Offset(21, 2.6), 1.5);
  }

  static void _sparkle(Canvas canvas, Paint fill, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final radius = i.isEven ? r : r * 0.32;
      final pt = c + Offset(math.cos(angle), math.sin(angle)) * radius;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), fill);
  }
}

typedef _Draw = void Function(Canvas canvas, Paint stroke, Paint fill);

class _LinePainter extends CustomPainter {
  _LinePainter(this.color, this.draw);

  final Color color;
  final _Draw draw;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    draw(canvas, stroke, fill);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}

/// Three ascending outlined bars, for Vocal Intensity.
class BarsIcon extends StatelessWidget {
  const BarsIcon({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LinePainter(color, _bars));

  static void _bars(Canvas canvas, Paint p, Paint fill) {
    for (final (x, h) in [(2.5, 7.0), (9.5, 12.0), (16.5, 17.0)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 21 - h, 5, h),
          const Radius.circular(2.5),
        ),
        p,
      );
    }
  }
}

/// A faint khatam-style lattice (overlapping square and diamond forming
/// eight-pointed stars), used as a quiet texture behind the header.
class LatticePainter extends CustomPainter {
  const LatticePainter({required this.color, this.cell = 34});

  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final half = cell / 2;
    final reach = half * 0.9;
    for (var y = 0.0; y < size.height + cell; y += cell) {
      for (var x = 0.0; x < size.width + cell; x += cell) {
        final c = Offset(x + half, y + half);
        canvas.drawRect(
          Rect.fromCenter(center: c, width: reach * 1.55, height: reach * 1.55),
          paint,
        );
        final diamond = Path()
          ..moveTo(c.dx, c.dy - reach)
          ..lineTo(c.dx + reach, c.dy)
          ..lineTo(c.dx, c.dy + reach)
          ..lineTo(c.dx - reach, c.dy)
          ..close();
        canvas.drawPath(diamond, paint);
      }
    }
  }

  @override
  bool shouldRepaint(LatticePainter old) =>
      old.color != color || old.cell != cell;
}
