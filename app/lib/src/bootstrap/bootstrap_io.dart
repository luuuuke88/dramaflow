import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../engine/compose.dart';
import '../engine/engine.dart';
import '../platform/avfoundation_composer.dart';
import '../state/providers.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final videoComposer =
      !kIsWeb && (Platform.isMacOS || Platform.isIOS || Platform.isAndroid)
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
