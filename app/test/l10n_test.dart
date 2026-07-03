import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ARB 文件中不存在空字符串译文（曾出现 key 存在但值为 "" 的半成品翻译，'
      'gen-l10n 的 untranslated 检查测不出这类问题）', () {
    for (final lang in ['zh', 'en', 'ja']) {
      final data = jsonDecode(
        File('lib/l10n/app_$lang.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final blanks = [
        for (final entry in data.entries)
          if (!entry.key.startsWith('@') &&
              entry.value is String &&
              (entry.value as String).trim().isEmpty)
            entry.key,
      ];
      expect(blanks, isEmpty,
          reason: 'app_$lang.arb 存在空字符串译文：$blanks');
    }
  });


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

  test('engine error keys have translations in all locales', () async {
    final locales = [
      await AppLocalizations.delegate.load(const Locale('zh')),
      await AppLocalizations.delegate.load(const Locale('en')),
      await AppLocalizations.delegate.load(const Locale('ja')),
    ];

    for (final l10n in locales) {
      expect(l10n.errProviderMissing, isNotEmpty);
      expect(l10n.errModelMissing, isNotEmpty);
      expect(l10n.errNetwork, isNotEmpty);
      expect(l10n.errLlmFormat, isNotEmpty);
      expect(l10n.errCanceled, isNotEmpty);
      expect(l10n.errAppRestart, isNotEmpty);
      expect(l10n.errFileTooLarge, isNotEmpty);
      expect(l10n.errFileType, isNotEmpty);
      expect(l10n.errRegexInvalid, isNotEmpty);
      expect(l10n.errNoChapters, isNotEmpty);
    }
  });
}
