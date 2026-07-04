import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production canvas visual parity evidence is anchored and reproducible',
      () {
    final doc = File(
      '../docs/superpowers/progress/2026-07-05-production-canvas-visual-parity.md',
    );
    expect(doc.existsSync(), isTrue);

    final text = doc.readAsStringSync();
    for (final required in [
      'Toonflow-web/src/views/production/index.vue',
      'Toonflow-web/src/views/production/utils/flowBuilder.ts',
      'app/lib/src/screens/production/production_screen.dart',
      'app/test/widgets/production_screen_test.dart',
      'app/tool/capture_production_visual_evidence_test.dart',
      'flutter test --update-goldens tool/capture_production_visual_evidence_test.dart',
      'visual-evidence/production-canvas/desktop-canvas.png',
      'visual-evidence/production-canvas/mobile-tabs.png',
    ]) {
      expect(text, contains(required), reason: required);
    }

    for (final node in [
      'script',
      'scriptPlan',
      'assets',
      'storyboardTable',
      'storyboard',
      'workbench',
    ]) {
      expect(text, contains('`$node`'), reason: node);
    }

    for (final edge in [
      'script -> assets',
      'script -> scriptPlan',
      'scriptPlan -> storyboardTable',
      'storyboardTable -> storyboard',
      'storyboard -> workbench',
    ]) {
      expect(text, contains(edge), reason: edge);
    }

    for (final image in [
      '../docs/superpowers/progress/visual-evidence/production-canvas/desktop-canvas.png',
      '../docs/superpowers/progress/visual-evidence/production-canvas/mobile-tabs.png',
    ]) {
      final file = File(image);
      expect(file.existsSync(), isTrue, reason: image);
      expect(file.lengthSync(), greaterThan(1000), reason: image);
    }
  });
}
