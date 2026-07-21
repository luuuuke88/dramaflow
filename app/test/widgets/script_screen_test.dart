import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/screens/script/script_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  String Function(String system, String user, String stage)? textResult;

  @override
  Future<TextResult> generateText(
    String system,
    String user, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final fn = textResult;
    if (fn != null) return TextResult(fn(system, user, stage));
    return const TextResult('');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptFileSelector extends FileSelectorPlatform {
  final XFile file;
  int openFileCalls = 0;
  List<XTypeGroup>? acceptedTypeGroups;

  _ScriptFileSelector(this.file);

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async =>
      null;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openFileCalls++;
    this.acceptedTypeGroups = acceptedTypeGroups;
    return file;
  }
}

class _FailingScriptFileSelector extends FileSelectorPlatform {
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async =>
      null;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    throw StateError('the selected file is no longer readable');
  }
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _NoopGateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-script-ui-');
    db = openEngineDb(':memory:');
    gateway = _NoopGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    // 本文件不覆盖统一确认闸（由 policy_confirm_test.dart 负责）；关闸让
    // 资产提取等页面动作不必在每个用例额外点击确认。
    engine.config.update({'policy.confirmMoney': '0'});
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('scriptGen','script_gen_system','剧本生成系统词',NULL)",
    );
    engine.installScriptPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: '剧本移动端测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app(double width) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: ScriptScreen(projectId: projectId)),
          ),
        ),
      );

  testWidgets('移动端剧本页：批量添加两集并落库', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('批量添加'));
    await tester.pumpAndSettle();
    expect(find.text('批量添加'), findsWidgets);

    await tester.enterText(
      find.byType(TextField).last,
      '第1集 雪夜\n黑衣人来到山门。\n第2集 焦玉\n焦黑玉佩落在雪中。',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('已勾选：0字'), findsOneWidget,
        reason: 'ToonFlow 第二步默认不勾选任何分集');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(engine.scripts(projectId), isEmpty, reason: '没有勾选分集时保存只提示，不应写入剧本');
    await tester.tap(find.text('雪夜'));
    await tester.tap(find.text('焦玉'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已勾选：'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final scripts = engine.scripts(projectId);
    expect(scripts.map((s) => s.name), ['雪夜', '焦玉']);
    expect(find.text('雪夜'), findsOneWidget);
    expect(find.text('焦玉'), findsOneWidget);
  });

  testWidgets('移动端批量添加保留空集标题，并按集号分别保存', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量添加'));
    await tester.pumpAndSettle();
    final regexField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '自定义剧本拆分正则',
    );
    expect(regexField, findsOneWidget);
    await tester.enterText(regexField, r'/EP(\d+)/g');
    final contentField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.minLines == 9,
    );
    expect(contentField, findsOneWidget);
    await tester.enterText(
      contentField,
      'EP1\n第一集正文。\nEP2\n第二集正文。',
    );
    await tester.pumpAndSettle();
    expect(find.text('已解析 2 章节'), findsOneWidget);
    final nextStep = find.widgetWithText(FilledButton, '下一步');
    expect(tester.widget<FilledButton>(nextStep).onPressed, isNotNull);
    await tester.tap(nextStep);
    await tester.pumpAndSettle();
    expect(find.text('第1集'), findsOneWidget);
    expect(find.text('第2集'), findsOneWidget);
    await tester.tap(find.text('第1集'));
    await tester.tap(find.text('第2集'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final scripts = engine.scripts(projectId);
    expect(scripts, hasLength(2));
    expect(scripts.map((script) => script.name), ['', '']);
    expect(scripts.map((script) => script.content), ['第一集正文。', '第二集正文。']);
  });

  testWidgets('桌面端新增剧本可拖入 txt 正文并保存', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();

    final dropTarget = find.byKey(const Key('script-file-drop'));
    expect(dropTarget, findsOneWidget,
        reason: 'ToonFlow 的单剧本上传区支持 Finder 拖入，桌面 Flutter 也必须有投放目标');
    final target = tester.widget<DropTarget>(dropTarget);
    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            Uint8List.fromList(utf8.encode('拖入正文第一场')),
            name: 'finder-script.txt',
            mimeType: 'text/plain',
            path: '/tmp/finder-script.txt',
          ),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.last.controller!.text, '拖入正文第一场');
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '剧本名称',
      ),
      'Finder 导入剧本',
    );
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    final saved = engine.scripts(projectId).single;
    expect(saved.name, 'Finder 导入剧本');
    expect(saved.content, '拖入正文第一场');
  });

  testWidgets('桌面端新增剧本点击上传 txt 后填入正文', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _ScriptFileSelector(
      XFile.fromData(utf8.encode('点击上传的正文'), path: 'picked-script.txt'),
    );
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file_outlined));
    await tester.pumpAndSettle();

    expect(selector.openFileCalls, 1);
    expect(selector.acceptedTypeGroups, isEmpty,
        reason: 'ToonFlow 没有 accept 限制，需让应用统一给出 doc/未知格式提示');
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.last.controller!.text, '点击上传的正文');
  });

  testWidgets('桌面端新增剧本点击选择旧 doc 时提示转换格式', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _ScriptFileSelector(
      XFile.fromData(Uint8List.fromList(<int>[0, 1, 2]),
          path: 'legacy-script.doc'),
    );
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file_outlined));
    await tester.pump();

    expect(
      find.widgetWithText(SnackBar, '.doc文件不支持解析,请转换为.txt或.docx文件'),
      findsOneWidget,
    );
  });

  testWidgets('桌面端新增剧本点击上传读取失败时显示错误提示', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _FailingScriptFileSelector();
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file_outlined));
    await tester.pump();

    expect(find.widgetWithText(SnackBar, '文件读取失败'), findsOneWidget);
  });

  testWidgets('桌面端新增剧本点击上传超过 10MB 时拒绝文件', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _ScriptFileSelector(
      XFile.fromData(Uint8List(10 * 1024 * 1024 + 1),
          path: 'oversized-script.txt'),
    );
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file_outlined));
    await tester.pump();

    expect(
        find.widgetWithText(SnackBar, '文件大小超过10MB，请上传更小的文件'), findsOneWidget);
  });

  testWidgets('桌面端新增剧本拖入旧 doc 时提示转换格式', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();

    final target =
        tester.widget<DropTarget>(find.byKey(const Key('script-file-drop')));
    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            Uint8List.fromList(<int>[0, 1, 2]),
            name: 'legacy-script.doc',
            mimeType: 'application/msword',
            path: '/tmp/legacy-script.doc',
          ),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();

    expect(
      find.widgetWithText(SnackBar, '.doc文件不支持解析,请转换为.txt或.docx文件'),
      findsOneWidget,
      reason: 'ToonFlow addScript.vue 对 application/msword 给出转换格式的专门提示',
    );
  });

  testWidgets('新增剧本可多选角色和场景资产并保存关联', (tester) async {
    final roleId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final sceneId = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门雪夜', describe: '场景');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '不应出现的音频', describe: '音频');
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '选择资产'));
    await tester.pumpAndSettle();

    expect(find.text('林朝雪'), findsOneWidget);
    expect(find.text('山门雪夜'), findsOneWidget);
    expect(find.text('不应出现的音频'), findsNothing, reason: '原版选择器只提供角色、道具和场景资产');
    await tester.tap(find.text('林朝雪'));
    await tester.tap(find.text('山门雪夜'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(find.text('林朝雪'), findsOneWidget);
    expect(find.text('山门雪夜'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '剧本名称',
      ),
      '关联素材剧本',
    );
    await tester.enterText(find.byType(TextField).last, '正文');
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    final saved = engine.scripts(projectId).single;
    expect(saved.relatedAssets.map((asset) => asset.id).toSet(),
        {roleId, sceneId});
  });

  testWidgets('关联资产选择器可搜索分页并选择衍生资产', (tester) async {
    final parentId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '第 1 位角色',
      describe: '',
    );
    final childId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '第 1 位角色-战损',
      describe: '',
      parentAssetsId: parentId,
    );
    for (var index = 2; index <= 10; index++) {
      engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '第 $index 位角色',
        describe: '',
      );
    }
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '选择资产'));
    await tester.pumpAndSettle();

    expect(find.text('第 10 位角色'), findsNothing, reason: '资产选择器每页最多显示 10 条');
    await tester.tap(find.byKey(const ValueKey('asset-picker-next')));
    await tester.pumpAndSettle();
    expect(find.text('第 10 位角色'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('asset-picker-search')),
      '战损',
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 位角色-战损'), findsOneWidget);
    await tester.tap(find.text('第 1 位角色-战损'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-picker-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('第 1 位角色-战损'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '剧本名称',
      ),
      '衍生资产剧本',
    );
    await tester.enterText(find.byType(TextField).last, '正文');
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(engine.scripts(projectId).single.relatedAssets.single.id, childId);
  });

  testWidgets('新增剧本在名称和正文都为空时先提示填写正文', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pump();

    expect(find.widgetWithText(SnackBar, '请上传或输入剧本内容'), findsOneWidget,
        reason: 'ToonFlow addScript.vue 先校验正文，再校验名称');
    expect(engine.scripts(projectId), isEmpty);
  });

  testWidgets('移动端新增单剧本使用全屏表单且可保存', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing,
        reason: '390dp 不应压缩桌面对话框，而要使用全屏编辑器');
    expect(find.text('新增剧本'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '剧本名称',
      ),
      '移动单剧本',
    );
    await tester.enterText(find.byType(TextField).last, '移动端粘贴正文');
    final confirm = find.widgetWithText(FilledButton, '确认');
    expect(confirm.hitTestable(), findsOneWidget,
        reason: '移动端表单的确认操作必须无需滚动到页面末尾即可点击');
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(engine.scripts(projectId).single.name, '移动单剧本');
    expect(engine.scripts(projectId).single.content, '移动端粘贴正文');
  });

  testWidgets('新增剧本超过项目单集字数上限时禁用确认', (tester) async {
    engine.config.update({'scriptEpisodeLength': '4'});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建剧本').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '超过四字的正文');
    await tester.pumpAndSettle();

    expect(find.text('7/4'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认'))
            .onPressed,
        isNull);
  });

  testWidgets('剧本页在移动与桌面端都不暴露从事件生成剧本入口', (tester) async {
    db.execute(
      "INSERT INTO o_novel (projectId,chapterIndex,reel,chapter,chapterData,eventState,event) "
      "VALUES (?,1,'正文卷','雪夜','山门雪夜',1,'事件一')",
      [projectId],
    );
    final novelId = db.select('SELECT id FROM o_novel').first['id'] as int;
    db.execute(
        "INSERT INTO o_event (name,detail,createTime) VALUES ('雪夜破门','详情',1)");
    final eventId = db.select('SELECT id FROM o_event').first['id'] as int;
    db.execute(
      'INSERT INTO o_eventChapter (eventId,novelId) VALUES (?,?)',
      [eventId, novelId],
    );

    for (final width in [390.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(app(width));
      await tester.pumpAndSettle();

      expect(find.text('事件生成剧本'), findsNothing,
          reason: 'ToonFlow 1.1.8 的 /script 页面没有事件选择或生成入口');
      expect(find.text('选择事件生成剧本'), findsNothing);
      expect(
          db
              .select(
                  "SELECT COUNT(*) n FROM o_tasks WHERE taskClass='script_generation'")
              .single['n'],
          0);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('移动端剧本页：编辑已有剧本并落库刷新', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '旧名', content: '旧内容');

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.text('旧名'));
    await tester.pumpAndSettle();
    expect(find.text('剧本详情'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新名');
    await tester.enterText(find.byType(TextField).last, '新内容第一场');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).single;
    expect(row.name, '新名');
    expect(row.content, '新内容第一场');
    expect(find.text('新名'), findsOneWidget);
    expect(find.text('旧名'), findsNothing);
  });

  testWidgets('移动端剧本页：编辑器支持 Markdown 格式工具和预览', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '旧名', content: '旧内容');

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.text('旧名'));
    await tester.pumpAndSettle();
    expect(find.text('剧本详情'), findsOneWidget);
    expect(find.byTooltip('加粗'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '新内容第一场');
    await tester.tap(find.byTooltip('加粗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('重点'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).single;
    expect(row.content, contains('**重点**'));
  });

  testWidgets('桌面剧本页：编辑器支持 Markdown 格式工具和预览', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '第一集', content: '# 开场');

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第一集'));
    await tester.pumpAndSettle();
    expect(find.text('剧本详情'), findsOneWidget);
    expect(find.byTooltip('标题'), findsOneWidget);
    expect(find.byTooltip('台词'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '正文');
    await tester.tap(find.byTooltip('台词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('角色：台词'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).single;
    expect(row.content, contains('> 角色：台词'));
  });

  testWidgets('移动端剧本页：卡片宽度不超出视口，删除按钮无需悬停即可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '待删本', content: '内容');

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Bug 1：卡片曾经硬编码 width:400，在 <400px 的手机视口上必然溢出。
    final cardSize = tester.getSize(find.byType(AnimatedContainer).first);
    expect(cardSize.width, lessThanOrEqualTo(390), reason: '卡片宽度不应超过 390pt 视口');

    // Bug 2：删除按钮曾经只在 MouseRegion hover 时显示，触屏端不可达。
    // 手机宽度下不做任何 hover 动作，直接确认其常显且可点。
    final deleteOpacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(deleteOpacity.opacity, 1.0, reason: '窄屏下删除按钮应无需悬停即可见');

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确认删除'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(engine.scripts(projectId).map((s) => s.name), ['待删本']);
  });

  testWidgets('移动壳平板宽度下剧本删除按钮仍无需 hover', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '平板待删本', content: '内容');

    await tester.pumpWidget(app(800));
    await tester.pumpAndSettle();

    final deleteOpacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(deleteOpacity.opacity, 1.0);
  });
}
