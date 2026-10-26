import 'package:flutter/material.dart';

/// Colours sampled from the DeenVoice Create Song reference design.
abstract final class DeenColors {
  static const background = Color(0xFF00100E);
  static const panel = Color(0xFF011513);
  static const panelEdge = Color(0xFF233B34);

  static const surface = Color(0xFF0A1516);
  static const surfaceRaised = Color(0xFF101A1C);
  static const field = Color(0xFF0D191A);
  static const border = Color(0xFF2A3739);
  static const borderStrong = Color(0xFF3A484A);

  static const gold = Color(0xFFF8C264);
  static const goldBright = Color(0xFFFFD36C);
  static const goldDeep = Color(0xFFF0B24A);
  static const goldBorder = Color(0xFFEAC169);
  static const onGold = Color(0xFF17120A);
  static const selectedFill = Color(0xFF25271A);

  static const purple = Color(0xFFA26EFC);

  static const textPrimary = Color(0xFFF7F8F6);
  static const textSecondary = Color(0xFFB8BEBE);
  static const textMuted = Color(0xFF99A2A4);
  static const placeholder = Color(0xFF8A9296);

  static const danger = Color(0xFFFF8A80);
}

/// Type scale. Sizes are in logical points and were fitted to the reference
/// by measuring rendered text widths against the bundled font files.
///
/// Note: the reference's body sizes (7–10 pt) are small for a phone. They are
/// kept for fidelity; [DeenText.boost] raises every size uniformly if the
/// design is later relaxed for accessibility.
abstract final class DeenText {
  static const double boost = 1.0;

  static const _arabicFallback = ['NotoNaskhArabic'];

  static TextStyle _serif(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    FontStyle? style,
  }) => TextStyle(
    fontFamily: 'PlayfairDisplay',
    fontFamilyFallback: _arabicFallback,
    fontSize: size * boost,
    fontWeight: weight,
    fontStyle: style,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
    letterSpacing: 0,
  );

  static TextStyle _sans(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: _arabicFallback,
    fontSize: size * boost,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
    // Explicit: Material 3's default text styles (inherited by every Text and
    // TextField) add 0.25-0.5pt of tracking, which widened all text ~5%.
    letterSpacing: letterSpacing ?? 0,
  );

  // dart format off
  // Sizes (pt) fitted so rendered text widths match the reference (text
  // extents measured on the reference, solved against the bundled font files,
  // checked with tool/compare_render.py).
  static TextStyle wordmark(Color c) => _serif(21,    FontWeight.w500, c, height: 1.1);
  static final tagline         = _sans(7,     FontWeight.w500, DeenColors.textSecondary, height: 1.2, letterSpacing: 0.46);
  static final screenTitle     = _serif(29.6, FontWeight.w700, DeenColors.textPrimary,   height: 1.1);
  static final screenSubtitle  = _sans(10.5,  FontWeight.w400, DeenColors.textSecondary, height: 1.48);
  static final stepLabel       = _sans(8.85,  FontWeight.w500, DeenColors.textPrimary,   height: 1.2);
  static final stepNumber      = _sans(9.5,   FontWeight.w600, DeenColors.textSecondary, height: 1.0);
  static final sectionTitle    = _serif(12.9, FontWeight.w600, DeenColors.textPrimary,   height: 1.2);
  static final sectionHint     = _sans(8,     FontWeight.w400, DeenColors.textMuted,     height: 1.3);
  static final cardTitle       = _sans(8.5,   FontWeight.w600, DeenColors.textPrimary,   height: 1.25);
  static final cardDescription = _sans(7.15,  FontWeight.w400, DeenColors.textSecondary, height: 1.5);
  static final chipLabel       = _sans(7.9,   FontWeight.w400, DeenColors.textPrimary,   height: 1.2);
  static final chipLabelGold   = _sans(7.9,   FontWeight.w500, DeenColors.gold,          height: 1.2);
  static final fieldLabel      = _sans(9.15,  FontWeight.w400, DeenColors.textPrimary,   height: 1.2);
  static final fieldValue      = _sans(8.6,   FontWeight.w500, DeenColors.textPrimary,   height: 1.2);
  static final fieldSubvalue   = _sans(7.3,   FontWeight.w400, DeenColors.textMuted,     height: 1.2);
  static final input           = _sans(10,    FontWeight.w400, DeenColors.textPrimary,   height: 1.7);
  static final inputPlaceholder= _sans(10,    FontWeight.w400, DeenColors.placeholder,   height: 1.7);
  static final counter         = _sans(9.15,  FontWeight.w400, DeenColors.textMuted,     height: 1.2);
  static final advancedTitle   = _sans(9.1,   FontWeight.w500, DeenColors.textPrimary,   height: 1.2);
  static final advancedHint    = _sans(7.3,   FontWeight.w400, DeenColors.textMuted,     height: 1.2);
  static final generateLabel   = _serif(13.4, FontWeight.w800, DeenColors.onGold,        height: 1.1);
  static final generateCost    = _sans(10.2,  FontWeight.w500, DeenColors.onGold,        height: 1.1);
  static final credits         = _sans(9.4,   FontWeight.w500, DeenColors.textPrimary,   height: 1.1);
  static final body            = _sans(11,    FontWeight.w400, DeenColors.textSecondary, height: 1.45);
  static final bodyStrong      = _sans(11,    FontWeight.w600, DeenColors.textPrimary,   height: 1.4);
  static final sheetTitle      = _serif(16,   FontWeight.w600, DeenColors.textPrimary,   height: 1.2);
  static final error           = _sans(9,     FontWeight.w400, DeenColors.danger,        height: 1.35);
  // dart format on
}

ThemeData buildDeenTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: DeenColors.background,
    colorScheme: const ColorScheme.dark(
      primary: DeenColors.gold,
      onPrimary: DeenColors.onGold,
      secondary: DeenColors.gold,
      surface: DeenColors.surface,
      onSurface: DeenColors.textPrimary,
      error: DeenColors.danger,
    ),
  );
  return base.copyWith(
    splashFactory: InkRipple.splashFactory,
    splashColor: DeenColors.gold.withValues(alpha: 0.08),
    highlightColor: DeenColors.gold.withValues(alpha: 0.04),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: DeenColors.gold,
      selectionColor: DeenColors.gold.withValues(alpha: 0.3),
      selectionHandleColor: DeenColors.gold,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DeenColors.surfaceRaised,
      contentTextStyle: DeenText.body.copyWith(color: DeenColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DeenColors.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DeenColors.panel,
      modalBackgroundColor: DeenColors.panel,
      showDragHandle: true,
      dragHandleColor: DeenColors.borderStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeenColors.panelEdge),
      ),
    ),
  );
}
