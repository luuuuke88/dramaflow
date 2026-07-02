import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/pipeline/schemas.dart';
import 'package:dramaflow/src/engine/util.dart';

void main() {
  group('parseScriptOut', () {
    test('合法输入，缺省字段补默认', () {
      final r = parseScriptOut({
        'episodes': [
          {
            'title': '雪夜来客',
            'scenes': [
              {'location': '山门', 'action': '守夜'}
            ]
          }
        ]
      });
      expect(r.episodes.single.synopsis, '');
      expect(r.episodes.single.scenes.single['timeOfDay'], '');
      expect(r.episodes.single.scenes.single['dialogues'], isEmpty);
    });
    test('空数组抛错', () {
      expect(() => parseScriptOut({'episodes': []}),
          throwsA(isA<EngineException>()));
    });
    test('缺 scenes 抛错', () {
      expect(
          () => parseScriptOut({
                'episodes': [
                  {'title': 'x'}
                ]
              }),
          throwsA(isA<EngineException>()));
    });
  });

  group('parseAssetsOut', () {
    test('prop 合法', () {
      final r = parseAssetsOut({
        'assets': [
          {'kind': 'prop', 'name': '霜纹玉'}
        ]
      });
      expect(r.single.kind, 'prop');
      expect(r.single.description, '');
    });
    test('kind 非法抛错并带原因', () {
      expect(
          () => parseAssetsOut({
                'assets': [
                  {'kind': 'weapon', 'name': 'x'}
                ]
              }),
          throwsA(predicate(
              (e) => e is EngineException && e.message.contains('weapon'))));
    });
  });

  group('parseShotsOut', () {
    test('imagePrompt 为空抛错', () {
      expect(
          () => parseShotsOut({
                'shots': [
                  {'description': 'x', 'imagePrompt': ''}
                ]
              }),
          throwsA(isA<EngineException>()));
    });
    test('合法输入 assetNames 规整为字符串', () {
      final r = parseShotsOut({
        'shots': [
          {
            'imagePrompt': 'a cat',
            'assetNames': ['陈默', 123]
          }
        ]
      });
      expect(r.single.assetNames, ['陈默', '123']);
    });
  });
}
