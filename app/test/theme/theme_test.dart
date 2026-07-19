import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自定义主色统一派生亮暗主题的品牌颜色', () {
    const primary = Color(0xFFE34D59);
    final defaultLight = buildTheme(Brightness.light);
    final defaultDark = buildTheme(Brightness.dark);
    final light = buildTheme(Brightness.light, primaryColor: primary);
    final dark = buildTheme(Brightness.dark, primaryColor: primary);
    final lightColors = light.extension<DFColors>()!;
    final darkColors = dark.extension<DFColors>()!;

    expect(light.colorScheme.primary, primary);
    expect(lightColors.primary, primary);
    expect(lightColors.primaryHover, isNot(defaultLight.colorScheme.primary));
    expect(lightColors.primarySubtle, isNot(defaultLight.extension<DFColors>()!.primarySubtle));
    expect(dark.colorScheme.primary, isNot(defaultDark.colorScheme.primary));
    expect(darkColors.primary, isNot(defaultDark.extension<DFColors>()!.primary));
    expect(lightColors.danger, defaultLight.extension<DFColors>()!.danger);
    expect(darkColors.danger, defaultDark.extension<DFColors>()!.danger);
  });
}
