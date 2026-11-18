import 'dart:math' as math;

import 'package:flutter/material.dart';

const ink = Color(0xFF0D0F12);
const surface = Color(0xFF191C22);
const text = Color(0xFFF5F5F7);
const mint = Color(0xFF6EE7B7);
const muted = Color(0xFF9DA4AD);
const line = Color(0xFF2B3138);
const mintSurface = Color(0xFF15231F);

ThemeData appTheme() {
  const colors = ColorScheme.dark(
    primary: mint,
    onPrimary: ink,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: muted,
    outlineVariant: line,
    error: text,
    onError: ink,
  );
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Manrope',
    colorScheme: colors,
  );
  return base.copyWith(
    scaffoldBackgroundColor: ink,
    applyElevationOverlayColor: false,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x99000000),
      modalElevation: 0,
      dragHandleColor: muted,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: mint,
      selectionColor: Color(0x446EE7B7),
      selectionHandleColor: mint,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: line),
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: const TextStyle(color: muted, fontSize: 15),
      labelStyle: const TextStyle(color: muted, fontSize: 14),
      counterStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: mint),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: const TextStyle(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: line),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

const heading = TextStyle(
  fontSize: 39,
  height: 1.08,
  letterSpacing: -1.7,
  fontWeight: FontWeight.w800,
);
const subheading = TextStyle(
  fontSize: 21,
  height: 1.2,
  letterSpacing: -0.55,
  fontWeight: FontWeight.w800,
);
const body = TextStyle(
  fontSize: 15,
  color: muted,
  height: 1.5,
  fontWeight: FontWeight.w500,
);
const label = TextStyle(
  fontSize: 12,
  height: 1.25,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.05,
  color: muted,
);

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = surface,
    this.border = line,
    this.radius = 22,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color border;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 33,
        height: 33,
        decoration: BoxDecoration(
          color: mint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const CustomPaint(painter: _BrandPainter()),
      ),
      const SizedBox(width: 9),
      const Text(
        'ThinkCaps',
        style: TextStyle(
          fontSize: 21,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
      ),
    ],
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 5);
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 1.65
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromLTRBR(-8, -4, 7, 4, const Radius.circular(4)),
      pen,
    );
    canvas.drawLine(const Offset(-0.5, -4), const Offset(-0.5, 4), pen);
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) => false;
}

class CardIllustration extends StatelessWidget {
  const CardIllustration({super.key});

  @override
  Widget build(BuildContext context) =>
      const ExcludeSemantics(child: CustomPaint(painter: _CardArt()));
}

class _CardArt extends CustomPainter {
  const _CardArt();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 154, size.height / 138);
    final inkPen = Paint()..color = mint.withValues(alpha: .16);
    for (var x = 5.0; x < 154; x += 10) {
      for (var y = 5.0; y < 138; y += 10) {
        final distance = (Offset(x, y) - const Offset(84, 65)).distance;
        if (distance < 75) canvas.drawCircle(Offset(x, y), .65, inkPen);
      }
    }
    void plate(
      Offset center,
      double angle,
      Color fill,
      Color border,
      String word,
    ) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final rect = RRect.fromLTRBR(-37, -47, 37, 47, const Radius.circular(13));
      canvas.drawRRect(rect, Paint()..color = fill);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke,
      );
      final glyph = TextPainter(
        text: TextSpan(
          text: word,
          style: const TextStyle(
            color: mint,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            fontFamily: 'Manrope',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2 - 1));
      glyph.dispose();
      canvas.restore();
    }

    plate(
      const Offset(103, 66),
      .25,
      const Color(0xFF1C322B),
      const Color(0xFF4B8B73),
      'Я',
    );
    plate(
      const Offset(66, 74),
      -.18,
      const Color(0xFF213B32),
      const Color(0xFF65B99A),
      'A',
    );
    final sparkle = Paint()
      ..color = mint
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(131, 10), const Offset(131, 24), sparkle);
    canvas.drawLine(const Offset(124, 17), const Offset(138, 17), sparkle);
    canvas.drawCircle(const Offset(17, 38), 2, sparkle);
  }

  @override
  bool shouldRepaint(_CardArt oldDelegate) => false;
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
    child: Column(
      children: [
        Icon(icon, size: 29, color: mint),
        const SizedBox(height: 12),
        Text(
          title,
          style: subheading.copyWith(fontSize: 17),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(detail, style: body, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class TranslationCredit extends StatelessWidget {
  const TranslationCredit({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/translation-attribution.png',
    width: 132,
    height: 12,
    alignment: Alignment.centerLeft,
    semanticLabel: 'Powered by Google Translate',
  );
}

void notifyUser(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
