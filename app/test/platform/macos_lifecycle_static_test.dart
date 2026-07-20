import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'macOS stays resident after the last window closes and restores on Dock activation',
      () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(
      source,
      contains('applicationShouldTerminateAfterLastWindowClosed'),
    );
    expect(
      RegExp(
        r'applicationShouldTerminateAfterLastWindowClosed[\s\S]*?\{\s*(?:return\s+)?false',
      ).hasMatch(source),
      isTrue,
      reason:
          'Closing the last macOS window must leave DramaFlow available in the Dock.',
    );
    expect(source, contains('applicationShouldHandleReopen'));
    expect(source, contains('window.makeKeyAndOrderFront'));
    expect(source, contains('NSApp.activate(ignoringOtherApps: true)'));
  });
}
