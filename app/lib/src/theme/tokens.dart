import 'package:flutter/material.dart';

@immutable
class DFColors extends ThemeExtension<DFColors> {
  final Color bg;
  final Color surface;
  final Color surfaceMuted;
  final Color stroke;
  final Color strokeStrong;
  final Color primary;
  final Color primaryHover;
  final Color primarySubtle;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color danger;
  final Color warning;
  final Color running;
  final Color focusRing;

  const DFColors({
    required this.bg,
    required this.surface,
    required this.surfaceMuted,
    required this.stroke,
    required this.strokeStrong,
    required this.primary,
    required this.primaryHover,
    required this.primarySubtle,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.danger,
    required this.warning,
    required this.running,
    required this.focusRing,
  });

  factory DFColors.light() {
    return const DFColors(
      bg: Color(0xFFF5F4F0),
      surface: Color(0xFFFFFFFF),
      surfaceMuted: Color(0xFFFAF9F6),
      stroke: Color(0xFFE7E4DD),
      strokeStrong: Color(0xFFD8D4CA),
      primary: Color(0xFF414CB2),
      primaryHover: Color(0xFF3540A0),
      primarySubtle: Color(0xFFEEEFFA),
      accent: Color(0xFFC97F1B),
      textPrimary: Color(0xFF201F1B),
      textSecondary: Color(0xFF6B685F),
      textTertiary: Color(0xFF97938A),
      success: Color(0xFF2E9E63),
      danger: Color(0xFFD9463E),
      warning: Color(0xFFDB8B1F),
      running: Color(0xFF414CB2),
      focusRing: Color(0x66414CB2),
    );
  }

  factory DFColors.dark() {
    return const DFColors(
      bg: Color(0xFF141419),
      surface: Color(0xFF1C1C24),
      surfaceMuted: Color(0xFF22222C),
      stroke: Color(0xFF2C2C38),
      strokeStrong: Color(0xFF3A3A48),
      primary: Color(0xFF8B93E8),
      primaryHover: Color(0xFFA0A7F0),
      primarySubtle: Color(0xFF262A45),
      accent: Color(0xFFE8A33D),
      textPrimary: Color(0xFFEDECE6),
      textSecondary: Color(0xFFA5A299),
      textTertiary: Color(0xFF6E6E7A),
      success: Color(0xFF4CC583),
      danger: Color(0xFFE86A62),
      warning: Color(0xFFD98E2B),
      running: Color(0xFF8B93E8),
      focusRing: Color(0x668B93E8),
    );
  }

  Color get card => surface;
  Color get cardHover => surfaceMuted;
  Color get primaryDim => primarySubtle;
  Color get green => success;
  Color get red => danger;
  Color get blue => primary;
  Color get grey => textTertiary;
  Color get textHi => textPrimary;
  Color get textMid => textSecondary;
  Color get textLo => textTertiary;

  @override
  DFColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceMuted,
    Color? stroke,
    Color? strokeStrong,
    Color? primary,
    Color? primaryHover,
    Color? primarySubtle,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? success,
    Color? danger,
    Color? warning,
    Color? running,
    Color? focusRing,
  }) {
    return DFColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      stroke: stroke ?? this.stroke,
      strokeStrong: strokeStrong ?? this.strokeStrong,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primarySubtle: primarySubtle ?? this.primarySubtle,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      running: running ?? this.running,
      focusRing: focusRing ?? this.focusRing,
    );
  }

  @override
  DFColors lerp(ThemeExtension<DFColors>? other, double t) {
    if (other is! DFColors) return this;
    return DFColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      strokeStrong: Color.lerp(strokeStrong, other.strokeStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primarySubtle: Color.lerp(primarySubtle, other.primarySubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      running: Color.lerp(running, other.running, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
    );
  }
}

abstract final class DFTokens {
  static const radiusShell = 16.0;
  static const radiusCard = 12.0;
  static const radiusControl = 8.0;
  static const radiusChip = 999.0;

  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;

  static const cardRest = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D201F1B),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const cardHover = <BoxShadow>[
    BoxShadow(
      color: Color(0x14201F1B),
      offset: Offset(0, 6),
      blurRadius: 20,
    ),
  ];

  static const dialog = <BoxShadow>[
    BoxShadow(
      color: Color(0x2E141419),
      offset: Offset(0, 24),
      blurRadius: 48,
    ),
  ];

  static const fast120 = Duration(milliseconds: 120);
  static const standard200 = Duration(milliseconds: 200);
  static const emphasized320 = Duration(milliseconds: 320);
  static const shimmer1200 = Duration(milliseconds: 1200);
  static const easeOutCubic = Curves.easeOutCubic;
  static const curve = easeOutCubic;

  static const display24w700 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );
  static const title20w700 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );
  static const section16w600 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );
  static const body14 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const caption12 = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const tabularFigures = <FontFeature>[FontFeature.tabularFigures()];
}
