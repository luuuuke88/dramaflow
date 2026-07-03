import 'audio_bind.dart';
import 'engine.dart';
import 'errors.dart';

extension StoryboardAudioApi on Engine {
  /// Bind an existing audio asset to a storyboard shot.
  ///
  /// The `audioPath/audioState/audioError` columns are reserved for generated
  /// per-shot TTS output. When an audio asset is bound manually, playback falls
  /// back through `audioAssetAbsPath`.
  void bindStoryboardAudio({
    required int storyboardId,
    int? audioAssetId,
    String? audioText,
  }) {
    _ensureStoryboard(storyboardId);
    if (audioAssetId != null) {
      final audio = db.select(
        "SELECT id FROM o_assets WHERE id=? AND type='audio'",
        [audioAssetId],
      ).firstOrNull;
      if (audio == null) {
        throw const EngineException(errPromptMissing, {'type': 'audioAsset'});
      }
    }
    db.execute(
      'UPDATE o_storyboard SET audioAssetId=?, audioText=?, '
      'audioPath=NULL, audioState=NULL, audioError=NULL WHERE id=?',
      [audioAssetId, audioText?.trim(), storyboardId],
    );
  }

  /// Ordered by storyboard index. A shot may have a generated `audioPath`, an
  /// audio asset binding, or no audio at all.
  List<String?> orderedStoryboardAudioPaths(int scriptId) {
    final rows = db.select(
      'SELECT audioPath,audioAssetId FROM o_storyboard '
      'WHERE scriptId=? ORDER BY "index" ASC',
      [scriptId],
    );
    return [
      for (final row in rows)
        _resolveStoryboardAudioPath(
          row['audioPath'] as String?,
          row['audioAssetId'] as int?,
        ),
    ];
  }

  String? _resolveStoryboardAudioPath(String? audioPath, int? audioAssetId) {
    if (audioPath != null && audioPath.isNotEmpty) {
      return media.absPath(audioPath);
    }
    if (audioAssetId == null) return null;
    return audioAssetAbsPath(audioAssetId);
  }

  void _ensureStoryboard(int storyboardId) {
    final row = db.select(
        'SELECT id FROM o_storyboard WHERE id=?', [storyboardId]).firstOrNull;
    if (row == null) {
      throw const EngineException(errPromptMissing, {'type': 'storyboard'});
    }
  }
}
