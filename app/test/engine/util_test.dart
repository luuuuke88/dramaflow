import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/util.dart';

void main() {
  group('newId', () {
    test('14位小写字母数字，且唯一', () {
      final a = newId(), b = newId();
      expect(a, matches(RegExp(r'^[0-9a-z]{14}$')));
      expect(a, isNot(equals(b)));
    });
  });

  group('extractJson', () {
    test('纯 JSON 直接解析', () {
      expect(extractJson('{"a":1}'), {'a': 1});
    });
    test('markdown 围栏内 JSON', () {
      expect(extractJson('前言\n```json\n{"a":1}\n```\n后记'), {'a': 1});
    });
    test('前后杂文取首尾括号', () {
      expect(extractJson('好的，结果是 {"a":[1,2]} 请查收'), {
        'a': [1, 2]
      });
    });
    test('无 JSON 抛 EngineException', () {
      expect(() => extractJson('没有json'), throwsA(isA<EngineException>()));
    });
  });

  group('errMessage', () {
    test('DioException 带响应体', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
            data: {'error': '上游炸了'}),
        message: 'bad',
      );
      final msg = errMessage(e);
      expect(msg, contains('HTTP 500'));
      expect(msg, contains('上游炸了'));
    });
    test('普通异常取 toString', () {
      expect(errMessage(EngineException('哦豁')), '哦豁');
    });
  });
}
