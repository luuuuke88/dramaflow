import 'package:flutter/material.dart';

/// DramaFlow 主题色板，由 ThemeExtension 注入到当前 Theme。
@immutable
class DFColors extends ThemeExtension<DFColors> {
  final Color bg;
  final Color surface;
  final Color card;
  final Color cardHover;
  final Color stroke;
  final Color primary;
  final Color primaryDim;
  final Color green;
  final Color red;
  final Color blue;
  final Color grey;
  final Color textHi;
  final Color textMid;
  final Color textLo;

  const DFColors({
    required this.bg,
    required this.surface,
    required this.card,
    required this.cardHover,
    required this.stroke,
    required this.primary,
    required this.primaryDim,
    required this.green,
    required this.red,
    required this.blue,
    required this.grey,
    required this.textHi,
    required this.textMid,
    required this.textLo,
  });

  @override
  DFColors copyWith({
    Color? bg,
    Color? surface,
    Color? card,
    Color? cardHover,
    Color? stroke,
    Color? primary,
    Color? primaryDim,
    Color? green,
    Color? red,
    Color? blue,
    Color? grey,
    Color? textHi,
    Color? textMid,
    Color? textLo,
  }) {
    return DFColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardHover: cardHover ?? this.cardHover,
      stroke: stroke ?? this.stroke,
      primary: primary ?? this.primary,
      primaryDim: primaryDim ?? this.primaryDim,
      green: green ?? this.green,
      red: red ?? this.red,
      blue: blue ?? this.blue,
      grey: grey ?? this.grey,
      textHi: textHi ?? this.textHi,
      textMid: textMid ?? this.textMid,
      textLo: textLo ?? this.textLo,
    );
  }

  @override
  DFColors lerp(ThemeExtension<DFColors>? other, double t) {
    if (other is! DFColors) return this;
    return DFColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardHover: Color.lerp(cardHover, other.cardHover, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDim: Color.lerp(primaryDim, other.primaryDim, t)!,
      green: Color.lerp(green, other.green, t)!,
      red: Color.lerp(red, other.red, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      grey: Color.lerp(grey, other.grey, t)!,
      textHi: Color.lerp(textHi, other.textHi, t)!,
      textMid: Color.lerp(textMid, other.textMid, t)!,
      textLo: Color.lerp(textLo, other.textLo, t)!,
    );
  }
}

abstract final class DF {
  static const radius = 14.0;

  static const light = DFColors(
    bg: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardHover: Color(0xFFF0F4F8),
    stroke: Color(0xFFE2E8F0),
    primary: Color(0xFF2563EB),
    primaryDim: Color(0xFFDBEAFE),
    green: Color(0xFF16A34A),
    red: Color(0xFFDC2626),
    blue: Color(0xFF2563EB),
    grey: Color(0xFF94A3B8),
    textHi: Color(0xFF0F172A),
    textMid: Color(0xFF475569),
    textLo: Color(0xFF94A3B8),
  );

  static const dark = DFColors(
    bg: Color(0xFF0D1017),
    surface: Color(0xFF141A23),
    card: Color(0xFF1A222E),
    cardHover: Color(0xFF212B3A),
    stroke: Color(0xFF2A3648),
    primary: Color(0xFFF6A821),
    primaryDim: Color(0xFF8A5E12),
    green: Color(0xFF3FB960),
    red: Color(0xFFE5534B),
    blue: Color(0xFF539BF5),
    grey: Color(0xFF768390),
    textHi: Color(0xFFF0F3F6),
    textMid: Color(0xFFADBAC7),
    textLo: Color(0xFF768390),
  );
}

extension DFThemeContext on BuildContext {
  DFColors get df => Theme.of(this).extension<DFColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final colors = isLight ? DF.light : DF.dark;
  final onPrimary = isLight ? Colors.white : const Color(0xFF1A1200);
  final scheme = isLight
      ? ColorScheme.light(
          primary: colors.primary,
          onPrimary: onPrimary,
          secondary: colors.blue,
          onSecondary: Colors.white,
          error: colors.red,
          onError: Colors.white,
          surface: colors.surface,
          onSurface: colors.textHi,
          surfaceContainerHighest: colors.card,
          outline: colors.stroke,
        )
      : ColorScheme.dark(
          primary: colors.primary,
          onPrimary: onPrimary,
          secondary: colors.blue,
          onSecondary: Colors.white,
          error: colors.red,
          onError: Colors.white,
          surface: colors.surface,
          onSurface: colors.textHi,
          surfaceContainerHighest: colors.card,
          outline: colors.stroke,
        );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[colors],
  );

  final inputFill = isLight ? colors.surface : colors.bg;
  final cardShadow =
      isLight ? Colors.black.withValues(alpha: 0.06) : Colors.transparent;

  return base.copyWith(
    scaffoldBackgroundColor: colors.bg,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
          titleLarge:
              base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium:
              base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: colors.textMid),
        )
        .apply(bodyColor: colors.textHi, displayColor: colors.textHi),
    cardTheme: CardThemeData(
      color: colors.card,
      elevation: isLight ? 1 : 0,
      margin: EdgeInsets.zero,
      shadowColor: cardShadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DF.radius),
        side: BorderSide(color: colors.stroke, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: onPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textHi,
        side: BorderSide(color: colors.stroke),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.primary),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.textMid),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      hintStyle: TextStyle(color: colors.textLo),
      labelStyle: TextStyle(color: colors.textMid),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryDim,
      selectedIconTheme: IconThemeData(color: colors.primary),
      unselectedIconTheme: IconThemeData(color: colors.textLo),
      selectedLabelTextStyle:
          TextStyle(color: colors.textHi, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: colors.textLo),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryDim,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textLo,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.textHi
              : colors.textLo,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primaryDim
              : colors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textMid,
        ),
        side: WidgetStateProperty.all(BorderSide(color: colors.stroke)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.stroke,
      thumbColor: colors.primary,
      overlayColor: colors.primary.withValues(alpha: 0.12),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(onPrimary),
      side: BorderSide(color: colors.stroke),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary
            : colors.grey,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary.withValues(alpha: 0.28)
            : colors.stroke,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.primary),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: colors.textHi),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.stroke),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.card,
      contentTextStyle: TextStyle(color: colors.textHi),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.stroke),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.stroke, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: colors.textHi,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: colors.textMid),
      actionsIconTheme: IconThemeData(color: colors.textMid),
    ),
  );
}
