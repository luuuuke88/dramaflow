import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'src/app.dart';
import 'src/engine/compose.dart';
import 'src/engine/engine.dart';
import 'src/platform/ffmpeg_kit_runner.dart';
import 'src/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final engine = await Engine.boot(
    dataDir: p.join(docs.path, 'dramaflow'),
    isMobile: isMobile,
    // 桌面端走系统进程 ffmpeg（可执行文件可打包分发，无动态库依赖）；
    // 移动端用 ffmpeg_kit（iOS/Android 构建自包含）。
    // macOS 不能用 ffmpeg_kit：其 macOS 框架链接 Homebrew 动态库，启动即崩且不可分发。
    ffmpegRunner:
        isMobile ? const FfmpegKitRunner() : const ProcessFfmpegRunner(),
  );
  runApp(ProviderScope(
    overrides: [engineProvider.overrideWithValue(engine)],
    child: const DramaFlowApp(),
  ));
}
