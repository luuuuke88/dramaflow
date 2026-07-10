import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'macOS debug keeps its data container without requiring keychain sharing',
      () {
    final debug =
        File('macos/Runner/DebugProfile.entitlements').readAsStringSync();
    final release =
        File('macos/Runner/Release.entitlements').readAsStringSync();

    expect(debug, contains('<key>com.apple.security.app-sandbox</key>'));
    expect(debug, isNot(contains('<key>keychain-access-groups</key>')));
    expect(release, contains('<key>com.apple.security.app-sandbox</key>'));
    expect(release, contains('<key>keychain-access-groups</key>'));
  });

  test('macOS signing can be configured without committing a developer team',
      () {
    final appConfig =
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
    final gitignore = File('macos/.gitignore').readAsStringSync();

    expect(appConfig, contains('#include? "Local.xcconfig"'));
    expect(gitignore, contains('Runner/Configs/Local.xcconfig'));
  });

  test('only macOS debug and profile project configs force ad-hoc signing', () {
    final project =
        File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(
      _projectConfig(project, '33CC10F92044A3C60003C045'),
      contains('CODE_SIGN_IDENTITY = "-";'),
    );
    expect(
      _projectConfig(project, '338D0CE9231458BD00FA5F75'),
      contains('CODE_SIGN_IDENTITY = "-";'),
    );
    expect(
      _projectConfig(project, '33CC10FA2044A3C60003C045'),
      isNot(contains('CODE_SIGN_IDENTITY = "-";')),
    );
  });
}

String _projectConfig(String project, String id) {
  final start = project.indexOf('\t\t$id ');
  if (start < 0) throw StateError('missing Xcode configuration $id');
  final end = project.indexOf('\n\t\t};', start);
  if (end < 0) throw StateError('unterminated Xcode configuration $id');
  return project.substring(start, end);
}
