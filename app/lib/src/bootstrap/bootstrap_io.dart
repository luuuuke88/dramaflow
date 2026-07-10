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

const _defaultSkillsZipAsset =
    'assets/default_skills/toonflow_default_skills.zip';
const _defaultPromptsZipAsset =
    'assets/default_prompts/toonflow_model_prompts.zip';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final dataDir = p.join(docs.path, 'dramaflow');
  await seedBundledDefaultSkills(dataDir);
  await seedBundledModelPrompts(dataDir);
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
  runApp(ProviderScope(
    overrides: [engineProvider.overrideWithValue(engine)],
    child: const DramaFlowApp(),
  ));
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
