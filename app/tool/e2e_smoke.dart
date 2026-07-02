// M0 验收冒烟：直接驱动内嵌引擎跑真实链路（azt gpt-5.5 + gpt-image-2）。
// 用法：dart run tool/e2e_smoke.dart <dataDir>
// 与 App 同一条代码路径（Engine.boot → 队列 → runners → providers）。
import 'dart:io';
import 'package:dramaflow/src/engine/engine.dart';

Future<void> waitJob(Engine e, String jobId,
    {Duration timeout = const Duration(minutes: 12)}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final rows =
        e.db.select('SELECT state, error, result FROM jobs WHERE id=?', [jobId]);
    final state = rows.first['state'] as String;
    if (state == 'done') {
      stdout.writeln('  ✅ ${rows.first['result']}');
      return;
    }
    if (state == 'failed' || state == 'canceled') {
      throw StateError('job $state: ${rows.first['error']}');
    }
    if (DateTime.now().isAfter(deadline)) throw StateError('等待超时');
    await Future<void>.delayed(const Duration(seconds: 5));
  }
}

Future<void> main(List<String> args) async {
  final dataDir = args.isNotEmpty ? args[0] : '/tmp/dramaflow-e2e';
  stdout.writeln('== M0 E2E（引擎内嵌，数据目录 $dataDir）==');
  final e = await Engine.boot(dataDir: dataDir, isMobile: false);

  stdout.writeln('[1/4] 建项目+导小说');
  final p = await e.createProject('E2E冒烟', artStyle: '国风水墨');
  await e.saveNovel(p.id,
      title: '剑出寒山',
      content: '寒山派守门弟子陈默雪夜守门，忽见黑衣人踏雪无痕而来，'
          '掷出半块焦黑的霜纹玉——那是十五年前随大师兄葬身火海的掌门信物。'
          '掌门沈青崖出关验玉，黑衣人自称大火唯一生还者，指认长老周鹤年当年锁谷害人。'
          '三人对质长老院密室，火盆中未烧尽的信纸露出"锁谷"二字，真相大白，'
          '黑衣人摘下斗篷，正是归来的大师兄裴无咎。');

  stdout.writeln('[2/4] 生成剧本（gpt-5.5，约1-2分钟）');
  await waitJob(e, await e.generateScript(p.id, episodeCount: 1));
  final eps = await e.listEpisodes(p.id);
  stdout.writeln('  剧集: ${eps.map((x) => '${x.idx}.${x.title}(${x.sceneCount}场)').join(' ')}');

  stdout.writeln('[3/4] 提取素材');
  await waitJob(e, await e.extractAssets(p.id));
  final assets = await e.listAssets(p.id);
  stdout.writeln('  素材: ${assets.map((a) => '[${a.kind}]${a.name}').join(' ')}');

  stdout.writeln('[4/4] 生成 1 张素材图（gpt-image-2，约2-6分钟）');
  final first = assets.firstWhere((a) => a.kind == 'character',
      orElse: () => assets.first);
  await waitJob(e, (await e.generateAssetImage(first.id))!);
  final done = (await e.listAssets(p.id))
      .firstWhere((a) => a.id == first.id);
  final abs = e.mediaAbsPath(done.imageUrl!);
  stdout.writeln('  图片: $abs (${File(abs).lengthSync()} bytes)');

  stdout.writeln('== 全链路通过 ==');
  e.dispose();
  exit(0);
}
