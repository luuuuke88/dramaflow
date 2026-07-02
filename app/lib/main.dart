import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'src/app.dart';
import 'src/engine/compose.dart';
import 'src/engine/engine.dart';
import 'src/platform/avfoundation_composer.dart';
import 'src/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final videoComposer = !kIsWeb && (Platform.isMacOS || Platform.isIOS)
      ? const AVFoundationComposer()
      : const UnsupportedComposer();
  final engine = await Engine.boot(
    dataDir: p.join(docs.path, 'dramaflow'),
    isMobile: isMobile,
    composer: videoComposer,
  );
  runApp(ProviderScope(
    overrides: [engineProvider.overrideWithValue(engine)],
    child: const DramaFlowApp(),
  ));
}
