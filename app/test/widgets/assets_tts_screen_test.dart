import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/assets/assets_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/desktop_drop_file.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Gateway implements ProviderGateway {
  late String Function(String rel) absPath;

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) async {
    expect(stage, 'tts');
    expect(text, '吾辈修士，何惧一战。');
    expect(voice, 'alloy');
    final rel = '$projectId/tts_ui.mp3';
    File(absPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([8, 8, 8]);
    return rel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioFileSelector extends FileSelectorPlatform {
  final List<XFile> files;
  int openFileCalls = 0;

  _AudioFileSelector(this.files);

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
    if (openFileCalls > files.length) {
      throw StateError('no queued test file');
    }
    return files[openFileCalls - 1];
  }
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-assets-tts-');
    final db = openEngineDb(':memory:');
    final gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    gateway.absPath = engine.mediaAbsPath;
    projectId = engine.addProject(projectType: 'novel', name: '配音 UI 测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({double width = 1400}) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: AssetsScreen(projectId: projectId)),
          ),
        ),
      );

  test('桌面拖入文件使用路径回退文件名并读取字节', () async {
    final dropped = DropItemFile.fromData(
      Uint8List.fromList(const [6, 7, 8]),
      path: '/tmp/path-fallback.ogg',
      mimeType: 'audio/ogg',
    );

    expect(droppedFileName(dropped), 'path-fallback.ogg');
    expect(await readDroppedFileBytes(dropped), const [6, 7, 8]);
  });

  testWidgets('音频 tab 可用文本配音创建可试听音频资产', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('文本配音'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tts-audio-name')), 'alloy');
    await tester.enterText(find.byKey(const Key('tts-audio-sex')), '男');
    await tester.enterText(find.byKey(const Key('tts-audio-describe')), '低音示例');
    await tester.enterText(
        find.byKey(const Key('tts-audio-text')), '吾辈修士，何惧一战。');
    await tester.enterText(find.byKey(const Key('tts-audio-voice')), 'alloy');
    await tester.tap(find.widgetWithText(FilledButton, '生成配音'));
    await tester.pumpAndSettle();

    expect(engine.audioPool(projectId).single.name, 'alloy');
    final audioId = engine.audioPool(projectId).single.id;
    expect(engine.audioAssetAbsPath(audioId), isNotNull);
    expect(
        File(engine.audioAssetAbsPath(audioId)!).readAsBytesSync(), [8, 8, 8]);
  });

  testWidgets('移动端音频 tab：文本配音创建音频资产', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('文本配音'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('tts-audio-name')), 'alloy');
    await tester.enterText(find.byKey(const Key('tts-audio-sex')), '男');
    await tester.enterText(find.byKey(const Key('tts-audio-describe')), '低音示例');
    await tester.enterText(
        find.byKey(const Key('tts-audio-text')), '吾辈修士，何惧一战。');
    await tester.enterText(find.byKey(const Key('tts-audio-voice')), 'alloy');
    await tester.tap(find.widgetWithText(FilledButton, '生成配音'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(engine.audioPool(projectId).single.name, 'alloy');
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('alloy')),
      findsOneWidget,
    );
  });

  testWidgets('桌面端音频 tab：新增两个本地音频条目并保存父子资产', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _AudioFileSelector([
      XFile.fromData(Uint8List.fromList(const [1, 2, 3]), path: 'voice-a.mp3'),
      XFile.fromData(Uint8List.fromList(const [9]), path: 'removed.wav'),
      XFile.fromData(Uint8List.fromList(const [4, 5, 6]), path: 'voice-b.m4a'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增音频').first);
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithLabel('音色'), '清冷女声');
    await tester.enterText(_fieldWithLabel('性别'), '女');
    await tester.enterText(_fieldWithLabel('描述').at(0), '清冷');
    await tester.tap(find.widgetWithText(OutlinedButton, '音频文件'));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 1);
    await tester.enterText(_fieldWithLabel('音频文本'), '第一句台词');
    await tester.enterText(_fieldWithLabel('描述').at(1), '平静');

    await tester.tap(find.widgetWithText(OutlinedButton, '添加音频'));
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'voice-a.mp3'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '音频文件'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '音频文件'));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 2);
    await tester.enterText(_fieldWithLabel('音频文本').at(1), '第二句台词');
    await tester.enterText(_fieldWithLabel('描述').at(2), '坚定');

    await tester.tap(find.byTooltip('删除').at(1));
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'voice-a.mp3'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '添加音频'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '音频文件'));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 3);
    await tester.enterText(_fieldWithLabel('音频文本').at(1), '第二句台词');
    await tester.enterText(_fieldWithLabel('描述').at(2), '坚定');

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final parent = engine.getAssets(projectId, type: 'audio').data.single;
    expect(parent.name, '清冷女声');
    expect(parent.sex, '女');
    expect(parent.audioDescribe, '清冷');
    expect(parent.sonAssets, hasLength(2));
    expect(parent.sonAssets.map((row) => row.prompt), ['第一句台词', '第二句台词']);
    expect(parent.sonAssets.map((row) => row.describe), ['平静', '坚定']);
    expect(
      parent.sonAssets
          .map((son) =>
              File(engine.mediaAbsPath(son.filePath!)).readAsBytesSync())
          .toList(),
      [
        const [1, 2, 3],
        const [4, 5, 6]
      ],
    );

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(_fieldWithLabel('音色'), '清冷女声（已修改）');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final updated = engine.getAssets(projectId, type: 'audio').data.single;
    expect(updated.name, '清冷女声（已修改）');
    expect(updated.sonAssets, hasLength(2));
    expect(
      updated.sonAssets
          .map((son) =>
              File(engine.mediaAbsPath(son.filePath!)).readAsBytesSync())
          .toList(),
      [
        const [1, 2, 3],
        const [4, 5, 6]
      ],
    );
  });

  testWidgets('移动端音频 tab：本地音频资产使用全屏表单保存', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _AudioFileSelector([
      XFile.fromData(Uint8List.fromList(const [4, 5]),
          path: 'mobile-voice.wav'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增音频').first);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.enterText(_fieldWithLabel('音色'), '移动音色');
    await tester.enterText(_fieldWithLabel('描述').at(0), '移动描述');
    await tester.tap(find.widgetWithText(OutlinedButton, '音频文件'));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 1);
    expect(find.text('mobile-voice.wav'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    final audioAssets = engine.getAssets(projectId, type: 'audio');
    expect(audioAssets.total, 1);
    final parent = audioAssets.data.single;
    expect(parent.name, '移动音色');
    expect(parent.audioDescribe, '移动描述');
    expect(parent.sonAssets, hasLength(1));
    expect(parent.sonAssets.single.filePath, endsWith('.wav'));
  });

  testWidgets('素材 tab：文件选择后落盘并刷新素材列表', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _AudioFileSelector([
      XFile.fromData(Uint8List.fromList(const [7, 4, 2, 9]),
          path: 'establishing-shot.mov'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('素材'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增素材').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 1);
    expect(find.text('establishing-shot.mov'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final clip = engine.getAssets(projectId, type: 'clip').data.single;
    expect(clip.name, 'establishing-shot');
    expect(clip.filePath, endsWith('.mov'));
    expect(
      File(engine.mediaAbsPath(clip.filePath!)).readAsBytesSync(),
      const [7, 4, 2, 9],
    );
    expect(find.text('establishing-shot'), findsOneWidget);
  });

  testWidgets('桌面端音频上传区可拖入 audio/* 文件并保存', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增音频').first);
    await tester.pumpAndSettle();

    final dropTarget = find.byKey(const Key('audio-file-drop-0'));
    expect(
      dropTarget,
      findsOneWidget,
      reason: 'ToonFlow 的每条音频上传区都是 Finder 拖放目标',
    );
    final target = tester.widget<DropTarget>(dropTarget);
    final dropped = DropItemFile.fromData(
      Uint8List.fromList(const [6, 7, 8]),
      name: 'dropped.ogg',
      mimeType: 'audio/ogg',
      path: '/tmp/dropped.ogg',
    );
    expect(dropped.name, 'dropped.ogg');
    expect(await dropped.readAsBytes(), const [6, 7, 8]);
    target.onDragDone!(
      DropDoneDetails(
        files: [dropped],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    expect(find.text('dropped.ogg'), findsOneWidget);

    await tester.enterText(_fieldWithLabel('音色'), '拖入音色');
    await tester.enterText(_fieldWithLabel('描述').at(0), '拖入描述');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final audio = engine.getAssets(projectId, type: 'audio').data.single;
    expect(audio.sonAssets.single.filePath, endsWith('.ogg'));
    expect(
      File(engine.mediaAbsPath(audio.sonAssets.single.filePath!))
          .readAsBytesSync(),
      const [6, 7, 8],
    );
  });
}

Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField(label: $label)',
    );
