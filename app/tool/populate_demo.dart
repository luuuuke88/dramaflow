// 演示数据填充：向指定 dataDir（App 容器）真实生成完整项目。
// 用法：dart run tool/populate_demo.dart <dataDir>
// ⚠️ 运行前必须退出 App（避免双引擎双队列操作同一库）。
// 生成量：2 集剧本 + 全部素材图 + 两集分镜 + 全部镜头图（视频留给用户真机点按）。
import 'dart:io';
import 'package:dramaflow/src/engine/engine.dart';

Future<void> waitIdle(Engine e, {Duration timeout = const Duration(minutes: 90)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final active = e.db.select(
        "SELECT COUNT(*) n FROM jobs WHERE state IN ('queued','running')").first['n'] as int;
    if (active == 0) return;
    await Future<void>.delayed(const Duration(seconds: 10));
  }
  throw StateError('等待队列空闲超时');
}

void report(Engine e, String pid) {
  final a = e.db.select(
      "SELECT status, COUNT(*) n FROM assets WHERE projectId=? GROUP BY status", [pid]);
  final s = e.db.select(
      "SELECT imageStatus, COUNT(*) n FROM shots WHERE projectId=? GROUP BY imageStatus", [pid]);
  stdout.writeln('  资产: ${a.map((r) => '${r['status']}:${r['n']}').join(' ')}');
  stdout.writeln('  镜头图: ${s.map((r) => '${r['imageStatus']}:${r['n']}').join(' ')}');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/populate_demo.dart <dataDir>');
    exit(2);
  }
  final e = await Engine.boot(dataDir: args[0], isMobile: false);
  stdout.writeln('== 演示项目填充（目标 ${args[0]}）==');

  final p = await e.createProject('剑出寒山', artStyle: '国风动漫，厚涂插画风');
  await e.saveNovel(p.id,
      title: '剑出寒山',
      content: File('${Directory.current.path}/tool/demo_novel.txt').readAsStringSync());

  stdout.writeln('[1/5] 剧本（2集）');
  await e.generateScript(p.id, episodeCount: 2);
  await waitIdle(e);

  stdout.writeln('[2/5] 素材提取');
  await e.extractAssets(p.id);
  await waitIdle(e);

  stdout.writeln('[3/5] 全部素材图（串行，较久）');
  await e.generateAllAssetImages(p.id);
  await waitIdle(e);
  report(e, p.id);

  stdout.writeln('[4/5] 两集分镜');
  for (final ep in await e.listEpisodes(p.id)) {
    await e.generateStoryboard(ep.id);
    await waitIdle(e);
  }

  stdout.writeln('[5/5] 全部镜头图（串行，最久）');
  for (final ep in await e.listEpisodes(p.id)) {
    await e.generateAllShotImages(ep.id);
  }
  await waitIdle(e);
  report(e, p.id);

  // 失败项自动补一轮
  final failedJobs = e.db.select(
      "SELECT id FROM jobs WHERE projectId=? AND state='failed' AND kind IN ('asset_image','shot_image')",
      [p.id]);
  if (failedJobs.isNotEmpty) {
    stdout.writeln('补跑 ${failedJobs.length} 个失败任务');
    for (final j in failedJobs) {
      try {
        await e.retryJob(j['id'] as String);
      } catch (_) {}
    }
    await waitIdle(e);
    report(e, p.id);
  }

  stdout.writeln('== 填充完成 ==');
  e.dispose();
  exit(0);
}
