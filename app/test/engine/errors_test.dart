import 'dart:convert';

import 'package:dramaflow/src/engine/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngineException', () {
    test('toReasonJson/fromReasonJson 往返保留 key 与 params', () {
      final error = EngineException(errNetwork, {
        'stage': 'event_generation',
        'status': 500,
        'retryable': true,
      });

      final restored = EngineException.fromReasonJson(error.toReasonJson());

      expect(restored, isNotNull);
      expect(restored!.errKey, errNetwork);
      expect(restored.errParams, {
        'stage': 'event_generation',
        'status': 500,
        'retryable': true,
      });
    });

    test('toReasonJson 输出稳定 reason 结构', () {
      final raw = jsonDecode(
        EngineException(errAppRestart).toReasonJson(),
      ) as Map<String, dynamic>;

      expect(raw, {
        'key': errAppRestart,
        'params': <String, dynamic>{},
      });
    });

    test('fromReasonJson 空值或非法 JSON 返回 null', () {
      expect(EngineException.fromReasonJson(null), isNull);
      expect(EngineException.fromReasonJson(''), isNull);
      expect(EngineException.fromReasonJson('{bad json'), isNull);
      expect(EngineException.fromReasonJson('[]'), isNull);
    });

    test('fromReasonJson 兼容缺 params 的旧 reason', () {
      final restored = EngineException.fromReasonJson('{"key":"$errCanceled"}');

      expect(restored, isNotNull);
      expect(restored!.errKey, errCanceled);
      expect(restored.errParams, isEmpty);
    });
  });
}
