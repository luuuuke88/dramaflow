import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('首次启动引导默认未完成，完成状态写入本地设置', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);
    final engine = Engine(
      db: db,
      media: MediaStore('/tmp/df-onboarding-engine-test-media'),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    addTearDown(engine.dispose);

    expect(engine.onboardingCompleted, isFalse);

    engine.completeOnboarding();

    expect(engine.onboardingCompleted, isTrue);
    expect(engine.config.str('onboarding.completed'), '1');
  });
}
