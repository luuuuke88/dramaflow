import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../engine/compose.dart';
import '../engine/engine.dart';
import '../platform/avfoundation_composer.dart';
import '../state/providers.dart';
import 'startup_failure_app.dart';

const _defaultSkillsZipAsset =
    'assets/default_skills/toonflow_default_skills.zip';
const _defaultPromptsZipAsset =
    'assets/default_prompts/toonflow_model_prompts.zip';

typedef StartupAppBuilder = Future<Widget> Function();
typedef StartupAppRunner = void Function(Widget app);

/// Verifies that the local app-data directory can be created and written before
/// startup touches bundled assets or SQLite.
Future<void> verifyDataDirectoryWritable(String dataDir) async {
  final directory = Directory(dataDir);
  await directory.create(recursive: true);
  final probe = File(p.join(
    dataDir,
    '.dramaflow-access-test-${DateTime.now().microsecondsSinceEpoch}',
  ));
  await probe.writeAsString('ok');
  await probe.delete();
}

Future<void> bootstrap({
  StartupAppBuilder? appBuilder,
  StartupAppRunner? runAppOverride,
  VoidCallback? exitOverride,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final attach = runAppOverride ?? runApp;
  // dart:io 的 exit() 在这个非 web 入口的所有目标平台（macOS/Windows/Linux/
  // Android/iOS）上都可用，不再像此前那样只给 macOS 提供退出路径——否则其他
  // 平台的用户一旦启动失败就会卡死在恢复页出不去。exitOverride 只用于测试
  // 场景替换掉真正的进程退出，避免单测跑到一半把 test runner 进程本身杀掉。
  final exitApp = exitOverride ?? () => exit(1);

  Future<void> start() async {
    try {
      attach(await (appBuilder ?? buildDramaFlowApp)());
    } catch (error, stackTrace) {
      final failure =
          error is StartupFailure ? error : StartupFailure(cause: error);
      // 完整错误文本 + 堆栈只进 debugPrint（仅开发者可见）是不够的——真实原因
      // 必须同时展示在 StartupFailureApp 里，见该文件的 _FailureDetails。
      debugPrint('DramaFlow startup failed: ${failure.cause}\n$stackTrace');
      attach(StartupFailureApp(
        failure: failure,
        onRetry: start,
        onExit: exitApp,
      ));
    }
  }

  await start();
}

Future<Widget> buildDramaFlowApp({
  String? dataDirectory,
  AssetBundle? bundle,
}) async {
  var dataDir = dataDirectory;
  try {
    if (dataDir == null) {
      final docs = await getApplicationDocumentsDirectory();
      dataDir = p.join(docs.path, 'dramaflow');
    }
    await verifyDataDirectoryWritable(dataDir);
    await seedBundledDefaultSkills(dataDir, bundle: bundle);
    await seedBundledModelPrompts(dataDir, bundle: bundle);
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final videoComposer =
        !kIsWeb && (Platform.isMacOS || Platform.isIOS || Platform.isAndroid)
            ? const AVFoundationComposer()
            : const UnsupportedComposer();
    final engine = await Engine.boot(
      dataDir: dataDir,
      isMobile: isMobile,
      composer: videoComposer,
    );
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: DramaFlowApp(
        initialOnboardingComplete: engine.onboardingCompleted,
      ),
    );
  } catch (error) {
    throw StartupFailure(cause: error, dataDirectory: dataDir);
  }
}

/// Copy bundled ToonFlow default visual/director manual files when absent.
///
/// A custom user pack must not suppress the rest of the bundled gallery, and
/// a matching local file must never be overwritten by an application update.
Future<void> seedBundledDefaultSkills(
  String dataDir, {
  AssetBundle? bundle,
}) async {
  await _seedArchivePrefix(
    dataDir: dataDir,
    asset: _defaultSkillsZipAsset,
    prefix: 'skills',
    bundle: bundle,
    allow: (parts) =>
        parts.length >= 3 &&
        (parts[1] == 'art_skills' || parts[1] == 'story_skills'),
  );
}

/// Copy bundled model prompt templates when their local files are absent.
///
/// Existing files are user-editable and are therefore never overwritten.
Future<void> seedBundledModelPrompts(
  String dataDir, {
  AssetBundle? bundle,
}) async {
  await _seedArchivePrefix(
    dataDir: dataDir,
    asset: _defaultPromptsZipAsset,
    prefix: 'model_prompts',
    bundle: bundle,
  );
}

Future<void> _seedArchivePrefix({
  required String dataDir,
  required String asset,
  required String prefix,
  AssetBundle? bundle,
  bool Function(List<String> parts)? allow,
}) async {
  final assetBundle = bundle ?? rootBundle;
  final zipBytes = await assetBundle.load(asset);
  final archive = ZipDecoder().decodeBytes(_byteDataToList(zipBytes));
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final parts = file.name.split('/');
    if (parts.length < 2 || parts.first != prefix) continue;
    if (allow != null && !allow(parts)) continue;
    final target = File(p.joinAll([dataDir, ...parts]));
    if (target.existsSync()) continue;
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(file.content as List<int>);
  }
}

List<int> _byteDataToList(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
