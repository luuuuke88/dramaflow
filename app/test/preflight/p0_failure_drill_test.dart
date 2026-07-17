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

const _model = 'doubao-seedance-2-0-mini-260615';

Future<({Engine engine, int projectId, int sbId})> _bootDrill(
    String sub) async {
  final workRoot = p.join(
      Platform.environment['HOME']!, 'Documents', 'dramaflow-p0-preflight');
  final dataDir = p.join(workRoot, 'drill-$sub');
  if (Directory(dataDir).existsSync()) {
    Directory(dataDir).deleteSync(recursive: true);
  }
  final credentials = InMemoryCredentialStore()
    ..seed(providerCredentialRef('volcengine'), 'drill-dummy-key');
  final engine = await Engine.boot(
    dataDir: dataDir,
    isMobile: false,
    credentialStore: credentials,
  );
  final db = engine.db;
  // baseUrl → 假上游（loopback），保留 inputValues 其他键。
  final row = db
      .select("SELECT inputValues FROM o_vendorConfig WHERE id='volcengine'")
      .first;
  final iv = (jsonDecode((row['inputValues'] as String?) ?? '{}') as Map)
      .cast<String, dynamic>();
  iv['baseUrl'] = 'http://127.0.0.1:8792/api/v3';
  db.execute("UPDATE o_vendorConfig SET inputValues=? WHERE id='volcengine'",
      [jsonEncode(iv)]);
  db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:$_model')");
  engine.saveVisualManual(
      name: 'P0视觉',
      pack: 'p0_pack',
      data: const {'art_storyboard_video': '预检'});
  final projectId = engine.addProject(
      projectType: 'novel', name: 'P0演练-$sub', artStyle: 'p0_pack');
  engine.editProject(projectId,
      videoModel: 'volcengine:$_model', videoRatio: '9:16');
  final scriptId =
      engine.addScript(projectId: projectId, name: 'P0', content: '预检');
  final sbId = engine.addStoryboard(
      projectId: projectId, scriptId: scriptId, prompt: '硬币在桌面缓慢旋转');
  final frame = File(engine.mediaAbsPath('p0/frame.png'))
    ..parent.createSync(recursive: true);
  File('/Users/luke/Documents/aivideo/azt-gpt-image2-test.png')
      .copySync(frame.path);
  db.execute(
      "UPDATE o_storyboard SET filePath='p0/frame.png' WHERE id=?", [sbId]);
  return (engine: engine, projectId: projectId, sbId: sbId);
}

Future<String> _waitTask(Engine engine, int taskId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final state = engine.db.select(
            'SELECT state FROM o_tasks WHERE id=?', [taskId]).first['state']
        as String;
    if (state == 'failed' || state == 'success') return state;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('演练任务 60s 未达终态');
}

void main() {
  test('p0 drill A: uncertain submission must not be resubmitted', () async {
    if (Platform.environment['P0_DRILL_CASE'] != 'uncertain') return;
    final ctx = await _bootDrill('uncertain');
    addTearDown(ctx.engine.dispose);
    final db = ctx.engine.db;

    final taskId = ctx.engine.batchGenerateVideos(ctx.projectId, [ctx.sbId]);
    expect(await _waitTask(ctx.engine, taskId), 'failed',
        reason: '假上游 500 必须以 failed 落库');
    final reason = db.select(
            'SELECT reason FROM o_tasks WHERE id=?', [taskId]).first['reason']
        as String?;
    expect(reason, isNotEmpty, reason: '失败原因必须可见（任务中心语义）');
    final sub = db
        .select('SELECT submissionState FROM o_video ORDER BY id DESC')
        .first['submissionState'];
    expect(sub, 'uncertain',
        reason: '提交异常必须落 uncertain（video_track.dart:812 语义）');

    // 核心断言：retryJob 面对 uncertain 不得重新提交。
    final candidatesBefore =
        db.select('SELECT count(*) c FROM o_video').first['c'] as int;
    Object? refusal;
    try {
      await ctx.engine.retryJob(taskId);
    } catch (e) {
      refusal = e;
    }
    final candidatesAfter =
        db.select('SELECT count(*) c FROM o_video').first['c'] as int;
    expect(candidatesAfter, candidatesBefore,
        reason: 'uncertain 重试不得产生新候选（防重复付费保护）');
    stdout.writeln(
        'P0_DRILL_UNCERTAIN_OK refusal=${refusal?.runtimeType ?? "silent-no-resubmit"}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('p0 drill B: accepted terminal failure retries with a new submission',
      () async {
    if (Platform.environment['P0_DRILL_CASE'] != 'acceptedFail') return;
    final ctx = await _bootDrill('accepted-fail');
    addTearDown(ctx.engine.dispose);
    final db = ctx.engine.db;

    final taskId = ctx.engine.batchGenerateVideos(ctx.projectId, [ctx.sbId]);
    expect(await _waitTask(ctx.engine, taskId), 'failed',
        reason: '轮询终态 failed 必须以 failed 落库');
    final row = db
        .select('SELECT submissionState, upstreamTaskId FROM o_video '
            'ORDER BY id DESC')
        .first;
    expect(row['submissionState'], 'accepted',
        reason: '假上游已返回任务 ID，提交态必须是 accepted');
    expect((row['upstreamTaskId'] as String?) ?? '', isNotEmpty);

    // 核心断言：accepted+终态失败允许 retryJob，产生第二次（假）提交。
    final retryTaskId = await ctx.engine.retryJob(taskId);
    expect(await _waitTask(ctx.engine, retryTaskId), 'failed',
        reason: '假上游仍确定性失败，但重试链路必须走通');
    final candidates = db.select('SELECT count(*) c FROM o_video').first['c'];
    stdout.writeln('P0_DRILL_ACCEPTED_FAIL_OK candidates=$candidates');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
