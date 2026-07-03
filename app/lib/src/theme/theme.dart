import 'package:flutter/material.dart';

import 'tokens.dart';

extension DFThemeContext on BuildContext {
  DFColors get df => Theme.of(this).extension<DFColors>()!;
}

abstract final class DF {
  static const radius = DFTokens.radiusCard;
}

ThemeData buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final colors = isLight ? DFColors.light() : DFColors.dark();
  final onPrimary = isLight ? Colors.white : colors.bg;
  final scheme = isLight
      ? ColorScheme.light(
          primary: colors.primary,
          onPrimary: onPrimary,
          secondary: colors.accent,
          onSecondary: Colors.white,
          error: colors.danger,
          onError: Colors.white,
          surface: colors.surface,
          onSurface: colors.textPrimary,
          surfaceContainerHighest: colors.surfaceMuted,
          outline: colors.stroke,
        )
      : ColorScheme.dark(
          primary: colors.primary,
          onPrimary: onPrimary,
          secondary: colors.accent,
          onSecondary: colors.bg,
          error: colors.danger,
          onError: colors.bg,
          surface: colors.surface,
          onSurface: colors.textPrimary,
          surfaceContainerHighest: colors.surfaceMuted,
          outline: colors.stroke,
        );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[colors],
  );

  final textTheme = base.textTheme
      .copyWith(
        headlineMedium: DFTokens.display24w700,
        titleLarge: DFTokens.title20w700,
        titleMedium: DFTokens.section16w600,
        bodyMedium: DFTokens.body14,
        bodySmall: DFTokens.caption12,
        labelSmall: DFTokens.caption12,
      )
      .apply(bodyColor: colors.textPrimary, displayColor: colors.textPrimary);

  return base.copyWith(
    scaffoldBackgroundColor: colors.bg,
    splashFactory: InkSparkle.splashFactory,
    textTheme: textTheme,
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: DFTokens.cardRest.first.color,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        side: BorderSide(color: colors.stroke, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: DFTokens.dialog.first.color,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.strokeStrong;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return colors.primaryHover;
          }
          return colors.primary;
        }),
        foregroundColor: WidgetStatePropertyAll(onPrimary),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
              horizontal: DFTokens.s20, vertical: DFTokens.s12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return colors.textTertiary;
          if (states.contains(WidgetState.hovered)) return colors.primary;
          return colors.textPrimary;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.hovered)
              ? colors.primary
              : colors.stroke;
          return BorderSide(color: color);
        }),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
              horizontal: DFTokens.s16, vertical: DFTokens.s12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return colors.textTertiary;
          if (states.contains(WidgetState.hovered)) return colors.primaryHover;
          return colors.primary;
        }),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceMuted,
      hintStyle: TextStyle(color: colors.textTertiary),
      labelStyle: TextStyle(color: colors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DFTokens.s12,
        vertical: DFTokens.s12,
      ),
      border: _inputBorder(colors.stroke),
      enabledBorder: _inputBorder(colors.stroke),
      focusedBorder: _inputBorder(colors.focusRing, width: 1.5),
      errorBorder: _inputBorder(colors.danger),
      focusedErrorBorder: _inputBorder(colors.danger, width: 1.5),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceMuted,
      selectedColor: colors.primarySubtle,
      disabledColor: colors.surfaceMuted,
      deleteIconColor: colors.textSecondary,
      labelStyle: DFTokens.caption12.copyWith(color: colors.textPrimary),
      secondaryLabelStyle: DFTokens.caption12.copyWith(color: colors.primary),
      side: BorderSide(color: colors.stroke),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DFTokens.s8),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primarySubtle,
      selectedIconTheme: IconThemeData(color: colors.primary),
      unselectedIconTheme: IconThemeData(color: colors.textTertiary),
      selectedLabelTextStyle:
          TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: colors.textTertiary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primarySubtle,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textTertiary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.textPrimary
              : colors.textTertiary,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primarySubtle
              : colors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textSecondary,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: colors.stroke)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
          ),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.stroke,
      thumbColor: colors.primary,
      overlayColor: colors.focusRing,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(onPrimary),
      side: BorderSide(color: colors.strokeStrong),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary
            : colors.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primarySubtle
            : colors.stroke,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.primary),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: colors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        side: BorderSide(color: colors.stroke),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface,
      contentTextStyle: TextStyle(color: colors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
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
      titleTextStyle: DFTokens.title20w700.copyWith(color: colors.textPrimary),
      iconTheme: IconThemeData(color: colors.textSecondary),
      actionsIconTheme: IconThemeData(color: colors.textSecondary),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(DFTokens.radiusControl),
    borderSide: BorderSide(color: color, width: width),
  );
}
