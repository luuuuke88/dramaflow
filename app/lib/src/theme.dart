import 'package:flutter/material.dart';

/// DramaFlow 视觉体系：深色影棚风。
/// 炭黑分层背景 + 琥珀主色（片场打板的暖调）+ 语义状态色。
abstract final class DF {
  // 背景层级（由深到浅）
  static const bg = Color(0xFF0D1017);
  static const surface = Color(0xFF141A23);
  static const card = Color(0xFF1A222E);
  static const cardHover = Color(0xFF212B3A);
  static const stroke = Color(0xFF2A3648);

  // 主色
  static const amber = Color(0xFFF6A821);
  static const amberDim = Color(0xFF8A5E12);

  // 语义状态
  static const green = Color(0xFF3FB960);
  static const red = Color(0xFFE5534B);
  static const blue = Color(0xFF539BF5);
  static const grey = Color(0xFF768390);

  // 文本
  static const textHi = Color(0xFFF0F3F6);
  static const textMid = Color(0xFFADBAC7);
  static const textLo = Color(0xFF768390);

  static const radius = 14.0;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: DF.amber,
    onPrimary: Color(0xFF1A1200),
    secondary: DF.blue,
    onSecondary: Colors.white,
    error: DF.red,
    onError: Colors.white,
    surface: DF.surface,
    onSurface: DF.textHi,
    surfaceContainerHighest: DF.card,
    outline: DF.stroke,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  return base.copyWith(
    scaffoldBackgroundColor: DF.bg,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          titleLarge: base.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleMedium:
              base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: DF.textMid),
        )
        .apply(bodyColor: DF.textHi, displayColor: DF.textHi),
    cardTheme: const CardThemeData(
      color: DF.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(DF.radius)),
        side: BorderSide(color: DF.stroke, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: DF.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DF.amber,
        foregroundColor: const Color(0xFF1A1200),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DF.textHi,
        side: const BorderSide(color: DF.stroke),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: DF.amber),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DF.bg,
      hintStyle: const TextStyle(color: DF.textLo),
      labelStyle: const TextStyle(color: DF.textMid),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: DF.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: DF.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: DF.amber, width: 1.5),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: DF.surface,
      indicatorColor: DF.amberDim,
      selectedIconTheme: IconThemeData(color: DF.amber),
      unselectedIconTheme: IconThemeData(color: DF.textLo),
      selectedLabelTextStyle:
          TextStyle(color: DF.textHi, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: DF.textLo),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: DF.surface,
      indicatorColor: DF.amberDim,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? DF.amber
                : DF.textLo),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color:
              states.contains(WidgetState.selected) ? DF.textHi : DF.textLo,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DF.card,
      contentTextStyle: const TextStyle(color: DF.textHi),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: DF.stroke),
      ),
    ),
    dividerTheme: const DividerThemeData(color: DF.stroke, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: DF.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: DF.textHi,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
  );
}
