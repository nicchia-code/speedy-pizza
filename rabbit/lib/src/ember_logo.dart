import 'dart:math' as math;

import 'package:flutter/material.dart';

const _ember = Color(0xFFE75B2C);
const _emberDeep = Color(0xFF9F321C);

class AnimatedEmberLogo extends StatefulWidget {
  const AnimatedEmberLogo({super.key, required this.size});

  final double size;

  @override
  State<AnimatedEmberLogo> createState() => _AnimatedEmberLogoState();
}

class _AnimatedEmberLogoState extends State<AnimatedEmberLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2EE75B2C),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: EmberLogoPainter(progress: _controller.value),
            );
          },
        ),
      ),
    );
  }
}

class EmberLogoPainter extends CustomPainter {
  const EmberLogoPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = math.min(size.width, size.height);
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;
    final center = Offset(size.width * 0.5, size.height * 0.56);
    final radius = shortestSide * (0.22 + pulse * 0.05);
    final glowPaint = Paint()
      ..color = _ember.withValues(alpha: 0.28 + pulse * 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    final basePaint = Paint()..color = const Color(0xFF402B24);
    final darkPaint = Paint()..color = const Color(0xFF2C201D);
    final emberPaint = Paint()
      ..color = Color.lerp(_emberDeep, const Color(0xFFFF8A32), pulse)!;
    final highlightPaint = Paint()
      ..color = const Color(0xFFFFBE75).withValues(alpha: 0.66 + pulse * 0.24)
      ..strokeWidth = shortestSide * 0.035
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(shortestSide * 0.24),
      ),
      Paint()..color = const Color(0xFFFFF4E8),
    );
    canvas.drawCircle(center, radius, glowPaint);

    _drawCoal(
      canvas,
      center + Offset(-shortestSide * 0.11, -shortestSide * 0.08),
      Size(shortestSide * 0.52, shortestSide * 0.2),
      -0.16,
      basePaint,
    );
    _drawCoal(
      canvas,
      center + Offset(shortestSide * 0.1, -shortestSide * 0.02),
      Size(shortestSide * 0.54, shortestSide * 0.2),
      0.14,
      darkPaint,
    );
    _drawCoal(
      canvas,
      center + Offset(-shortestSide * 0.02, shortestSide * 0.12),
      Size(shortestSide * 0.62, shortestSide * 0.22),
      -0.02,
      basePaint,
    );

    canvas.drawLine(
      center + Offset(-shortestSide * 0.22, shortestSide * 0.04),
      center + Offset(shortestSide * 0.1, -shortestSide * 0.02),
      highlightPaint,
    );
    canvas.drawLine(
      center + Offset(-shortestSide * 0.04, shortestSide * 0.16),
      center + Offset(shortestSide * 0.24, shortestSide * 0.08),
      highlightPaint,
    );
    canvas.drawCircle(
      center + Offset(-shortestSide * 0.16, shortestSide * 0.12),
      shortestSide * (0.075 + pulse * 0.02),
      emberPaint,
    );
  }

  void _drawCoal(
    Canvas canvas,
    Offset center,
    Size size,
    double rotation,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width,
          height: size.height,
        ),
        Radius.circular(size.height * 0.48),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EmberLogoPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
