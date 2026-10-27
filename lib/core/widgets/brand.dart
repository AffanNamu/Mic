import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/deen_theme.dart';

/// "DeenVoice" with "Deen" in gold.
class DeenWordmark extends StatelessWidget {
  const DeenWordmark({super.key, this.fontSize = 21});

  final double fontSize;

  @override
  Widget build(BuildContext context) => Text.rich(
    const TextSpan(
      children: [
        TextSpan(
          text: 'Deen',
          style: TextStyle(color: DeenColors.gold),
        ),
        TextSpan(
          text: 'Voice',
          style: TextStyle(color: DeenColors.textPrimary),
        ),
      ],
    ),
    style: DeenText.wordmark(DeenColors.textPrimary)
        .copyWith(fontSize: fontSize),
  );
}

/// The DeenVoice app icon, drawn from the bundled 384 px image.
class DeenAppIcon extends StatelessWidget {
  const DeenAppIcon({super.key, required this.size, this.glow = false});

  final double size;

  /// A soft gold halo, as on the Welcome screen.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/brand/deenvoice_icon_384.webp',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'DeenVoice',
    );
    if (!glow) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: DeenColors.gold.withValues(alpha: 0.28),
            blurRadius: size * 0.28,
          ),
        ],
      ),
      child: image,
    );
  }
}

/// The multicoloured Google "G", drawn as arcs. Only used for a button that is
/// shown disabled until Google sign-in exists.
class GoogleGMark extends StatelessWidget {
  const GoogleGMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _GPainter()),
  );
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final radius = s * 0.5 - stroke / 2;
    final rect = Rect.fromCircle(center: Offset(s / 2, s / 2), radius: radius);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    void arc(Color c, double fromDeg, double sweepDeg) {
      canvas.drawArc(
        rect,
        fromDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        p..color = c,
      );
    }

    const blue = Color(0xFF4285F4);
    arc(const Color(0xFFEA4335), 215, 100);
    arc(const Color(0xFFFBBC05), 135, 80);
    arc(const Color(0xFF34A853), 45, 90);
    arc(blue, 0, 45);
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke * 0.05, stroke),
      Paint()..color = blue,
    );
  }

  @override
  bool shouldRepaint(_GPainter oldDelegate) => false;
}
