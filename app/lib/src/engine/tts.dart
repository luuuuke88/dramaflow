import 'package:dio/dio.dart';

import 'assets.dart';
import 'engine.dart';
import 'errors.dart';

extension TtsApi on Engine {
  Future<int> addSynthesizedAudioAsset({
    required int projectId,
    required String name,
    required String sex,
    required String describe,
    required String text,
    String? voice,
    String? format,
    CancelToken? cancelToken,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw const EngineException(errPromptMissing, {'type': 'ttsText'});
    }
    final parentId = addAudioAssets(
      projectId: projectId,
      name: name.trim().isEmpty ? 'voice' : name.trim(),
      sex: sex.trim(),
      describe: describe.trim(),
      items: [
        (
          base64: null,
          ext: null,
          prompt: cleanText,
          name: name.trim().isEmpty ? 'voice' : name.trim(),
          describe: describe.trim(),
          existingImageId: null,
        ),
      ],
    );
    final child = db.select(
      'SELECT id FROM o_assets WHERE assetsId=? ORDER BY id DESC LIMIT 1',
      [parentId],
    );
    final childId = child.first['id'] as int;
    await synthesizeAudioAsset(
      audioAssetId: childId,
      text: cleanText,
      voice: voice,
      format: format,
      cancelToken: cancelToken,
    );
    return parentId;
  }

  /// Generate speech for an audio asset and attach the resulting media row.
  ///
  /// `audioAssetId` may be either an audio parent asset or one of its audio
  /// child entries. The latest generated file becomes the selected audio.
  Future<int> synthesizeAudioAsset({
    required int audioAssetId,
    required String text,
    String? voice,
    String? format,
    CancelToken? cancelToken,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw const EngineException(errPromptMissing, {'type': 'ttsText'});
    }

    final rows = db.select(
      "SELECT id,projectId,name,type FROM o_assets WHERE id=?",
      [audioAssetId],
    );
    if (rows.isEmpty || rows.first['type'] != 'audio') {
      throw const EngineException(errTaskUnsupported, {'type': 'audio'});
    }

    final projectId = (rows.first['projectId'] as int? ?? 0).toString();
    final voiceName = _voiceOrDefault(voice, rows.first['name'] as String?);
    final rel = await gateway.generateSpeech(
      cleanText,
      projectId,
      stage: 'tts',
      voice: voiceName,
      format: format,
      cancelToken: cancelToken,
    );

    final bindingRows =
        db.select('SELECT value FROM o_setting WHERE key=?', ['binding.tts']);
    final model = bindingRows.isEmpty ? null : bindingRows.first['value'];
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state,model) "
      "VALUES (?,?,'audio','已完成',?)",
      [audioAssetId, rel, model],
    );
    final imageId = db.lastInsertRowId;
    db.execute(
        'UPDATE o_assets SET imageId=? WHERE id=?', [imageId, audioAssetId]);
    return imageId;
  }
}

String _voiceOrDefault(String? override, String? assetName) {
  final explicit = override?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final candidate = assetName?.trim() ?? '';
  if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(candidate)) return candidate;
  return 'alloy';
}
