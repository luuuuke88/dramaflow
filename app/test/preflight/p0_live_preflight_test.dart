import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

const _model = 'doubao-seedance-2-0-mini-260615';

void main() {
  test('p0 live preflight', () async {
    final phase = Platform.environment['P0_PHASE'];
    if (Platform.environment['P0_LIVE'] != '1' || phase == null) {
      return; // 默认套件零副作用
    }
    final home = Platform.environment['HOME']!;
    final dataDir =
        p.join(home, 'Documents', 'dramaflow-p0-preflight', 'live-data');

    // key：旧库只读 → 进程内存。绝不打印、绝不写盘。
    final keyField = Platform.environment['P0_KEY_FIELD'] ?? 'apiKey';
    final tf = sq.sqlite3.open(
        p.join(home, 'Library/Application Support/toonflow/data/db2.sqlite'),
        mode: sq.OpenMode.readOnly);
    final keyRow = tf.select(
        "SELECT json_extract(inputValues, '\$.' || ?) AS k "
        "FROM o_vendorConfig WHERE id='volcengine'",
        [keyField]);
    final key = keyRow.isEmpty ? null : keyRow.first['k'] as String?;
    tf.close();
    if (key == null || key.isEmpty) {
      fail('旧库未取到 key（字段 $keyField）：走用户填入一次的退化路径');
    }
    final credentials = InMemoryCredentialStore()
      ..seed(providerCredentialRef('volcengine'), key);
    final engine = await Engine.boot(
      dataDir: dataDir,
      isMobile: false,
      credentialStore: credentials,
    );
    final db = engine.db;

    if (phase == 'submit') {
      final row = db
          .select(
              "SELECT inputValues FROM o_vendorConfig WHERE id='volcengine'")
          .first;
      final iv = (jsonDecode((row['inputValues'] as String?) ?? '{}') as Map)
          .cast<String, dynamic>();
      iv['baseUrl'] = 'http://127.0.0.1:8791/api/v3';
      db.execute(
          "UPDATE o_vendorConfig SET inputValues=? WHERE id='volcengine'",
          [jsonEncode(iv)]);
      db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
          "('binding.shot_video','volcengine:$_model')");
      // 最低成本档：声明能力里的最短时长 + 最低分辨率。
      final modelsRaw = db
          .select("SELECT models FROM o_vendorConfig WHERE id='volcengine'")
          .first['models'] as String?;
      final models = (jsonDecode(modelsRaw ?? '[]') as List).cast<Map>();
      final mini = models.firstWhere((m) => m['modelId'] == _model);
      final caps = ((mini['capabilities'] as Map?)?['video'] as Map?) ?? {};
      final durations =
          ((caps['durations'] as List?) ?? [5]).cast<num>().toList()..sort();
      final resolutions =
          ((caps['resolutions'] as List?) ?? ['720p']).cast<String>();
      final resolution =
          resolutions.contains('480p') ? '480p' : resolutions.first;
      db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
          "('videoResolution','$resolution')");
      db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
          "('videoDuration','${durations.first}')");

      engine.saveVisualManual(
          name: 'P0视觉',
          pack: 'p0_pack',
          data: const {'art_storyboard_video': '预检'});
      final projectId = engine.addProject(
          projectType: 'novel', name: 'P0真实预检', artStyle: 'p0_pack');
      engine.editProject(projectId,
          videoModel: 'volcengine:$_model', videoRatio: '9:16');
      final scriptId =
          engine.addScript(projectId: projectId, name: 'P0', content: '预检');
      final sbId = engine.addStoryboard(
          projectId: projectId,
          scriptId: scriptId,
          prompt: '一枚硬币在木桌上缓慢旋转，特写，柔和光线');
      final frame = File(engine.mediaAbsPath('p0/frame.png'))
        ..parent.createSync(recursive: true);
      File('/Users/luke/Documents/aivideo/azt-gpt-image2-test.png')
          .copySync(frame.path);
      db.execute(
          "UPDATE o_storyboard SET filePath='p0/frame.png' WHERE id=?", [sbId]);

      final taskId = engine.batchGenerateVideos(projectId, [sbId]);
      stdout.writeln('P0_MARK submitted taskId=$taskId '
          'resolution=$resolution duration=${durations.first}');
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        final rows = db.select("SELECT id, upstreamTaskId FROM o_video "
            "WHERE submissionState='accepted' AND upstreamTaskId IS NOT NULL");
        if (rows.isNotEmpty) {
          stdout.writeln(
              'P0_MARK upstream_persisted upstreamTaskId=${rows.first['upstreamTaskId']}');
          exit(9); // 硬杀：不给引擎任何收尾机会（模拟强制退出）
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('180s 内 upstreamTaskId 未持久化');
    }

    if (phase == 'resume') {
      // Engine.boot 已执行 recoverOnColdStart + queue.start：只等终态。
      final deadline = DateTime.now().add(const Duration(minutes: 20));
      while (DateTime.now().isBefore(deadline)) {
        final rows = db.select('SELECT upstreamState, filePath FROM o_video '
            'WHERE upstreamTaskId IS NOT NULL');
        if (rows.isNotEmpty) {
          final state = rows.first['upstreamState'] as String?;
          final filePath = rows.first['filePath'] as String?;
          if (state == 'succeeded' && filePath != null && filePath.isNotEmpty) {
            stdout.writeln('P0_MARK done filePath=$filePath');
            engine.dispose();
            return;
          }
          if (state == 'failed' || state == 'canceled') {
            fail('上游终态异常: $state');
          }
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      fail('20 分钟未达终态（记录后人工检查上游任务状态，勿重复提交）');
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
