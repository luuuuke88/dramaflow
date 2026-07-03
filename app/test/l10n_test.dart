import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads supported localizations', () async {
    for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n, isA<AppLocalizations>());
    }
  });

  test('menuMyProject is translated differently for each locale', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(zh.menuMyProject, isNotEmpty);
    expect(en.menuMyProject, isNotEmpty);
    expect(ja.menuMyProject, isNotEmpty);
    expect(
        {zh.menuMyProject, en.menuMyProject, ja.menuMyProject}, hasLength(3));
  });

  test('commonSave uses the required zh baseline value', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(zh.commonSave, '保存');
  });
}
