import 'dart:math' as math;

import 'package:flutter/material.dart';

class PlayingCard extends StatelessWidget {
  final int number, deck;
  final double width, height;
  final VoidCallback? onTap;
  final bool enabled;
  const PlayingCard({
    super.key,
    required this.number,
    required this.deck,
    this.width = 94,
    this.height = 132,
    this.onTap,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) {
    final hue = 145 * (1 - ((number - 1) / math.max(1, deck - 1)).clamp(0, 1));
    final empty = number == 0;
    final colors = empty
        ? const [Color(0xff29483d), Color(0xff142c2b)]
        : [
            HSLColor.fromAHSL(1, hue.toDouble(), .60, .79).toColor(),
            HSLColor.fromAHSL(1, hue.toDouble(), .35, .52).toColor(),
          ];
    final ink = empty
        ? const Color(0xffbcf582)
        : HSLColor.fromAHSL(1, hue.toDouble(), .45, .15).toColor();
    return Semantics(
      button: onTap != null,
      enabled: enabled,
      label: empty
          ? 'Mesa sin cartas'
          : onTap != null
          ? 'Jugar carta $number'
          : 'Última carta: $number',
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: enabled ? 1 : .55,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .28)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: enabled ? onTap : null,
                child: Stack(
                  children: [
                    Positioned(
                      top: 10,
                      left: 11,
                      child: Text(
                        empty ? '∞' : '$number',
                        style: TextStyle(color: ink, fontSize: 11),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            empty ? '◎' : '$number',
                            style: TextStyle(
                              color: ink,
                              fontSize: width * .46,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 11,
                      child: RotatedBox(
                        quarterTurns: 2,
                        child: Text(
                          empty ? '∞' : '$number',
                          style: TextStyle(color: ink, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrbitPainter extends CustomPainter {
  final double pulse;
  OrbitPainter(this.pulse);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate((i * 37 - 18) * math.pi / 180);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xffbcf582).withValues(alpha: .05 + pulse * .04);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * (.72 + i * .1),
          height: size.height * .55,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(OrbitPainter oldDelegate) => oldDelegate.pulse != pulse;
}

class Celebration extends CustomPainter {
  final double progress;
  Celebration(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(17);
    for (var i = 0; i < 45; i++) {
      final x = random.nextDouble() * size.width;
      final delay = random.nextDouble() * .3;
      final t = ((progress - delay) / .7).clamp(0.0, 1.0).toDouble();
      final hue = random.nextDouble() * 160;
      final paint = Paint()
        ..color = HSLColor.fromAHSL((1 - t).toDouble(), hue, .7, .7).toColor();
      canvas.save();
      canvas.translate(x, t * size.height);
      canvas.rotate(t * 8 + i);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 5, 10), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(Celebration oldDelegate) =>
      oldDelegate.progress != progress;
}
