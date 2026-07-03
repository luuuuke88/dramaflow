import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../util.dart';

const stageKindByStage = {
  'script_gen': 'text',
  'event_extract': 'text',
  'asset_extract': 'text',
  'storyboard_gen': 'text',
  'asset_image': 'image',
  'shot_image': 'image',
  'shot_video': 'video',
  'tts': 'tts',
};

class ResolvedModel {
  final String providerId;
  final String protocol;
  final String baseUrl;
  final String apiKey;
  final String modelId;

  const ResolvedModel({
    required this.providerId,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
  });
}

String requiredKindForStage(String stage) {
  final kind = stageKindByStage[stage];
  if (kind == null) {
    throw EngineException(errModelMissing, {'stage': stage});
  }
  return kind;
}

ResolvedModel resolveStage(Database db, String stage) {
  final requiredKind = requiredKindForStage(stage);
  final key = 'binding.$stage';
  final bindings = db.select('SELECT value FROM o_setting WHERE key=?', [key]);
  if (bindings.isEmpty || (bindings.first['value'] as String).trim().isEmpty) {
    throw EngineException(errModelMissing, {'stage': stage});
  }

  final value = bindings.first['value'] as String;
  final sep = value.indexOf(':');
  if (sep <= 0 || sep == value.length - 1) {
    throw EngineException(errModelMissing, {'stage': stage});
  }
  final providerId = value.substring(0, sep);
  final modelId = value.substring(sep + 1);

  final providers = db.select(
      'SELECT id, inputValues, models FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
      [providerId]);
  if (providers.isEmpty) {
    throw EngineException(
        errProviderMissing, {'stage': stage, 'providerId': providerId});
  }

  final p = providers.first;
  final inputValues = _jsonMap(p['inputValues']);
  final models = _jsonList(p['models']);
  Map<String, dynamic>? model;
  for (final item in models.whereType<Map>()) {
    final candidate = Map<String, dynamic>.from(item);
    if (candidate['modelId'] == modelId &&
        candidate['kind'] == requiredKind &&
        _enabled(candidate['enabled'])) {
      model = candidate;
      break;
    }
  }
  if (model == null) {
    throw EngineException(
        errModelMissing, {'stage': stage, 'modelId': modelId});
  }

  return ResolvedModel(
    providerId: p['id'] as String,
    protocol: inputValues['protocol'] as String? ?? 'openai_compatible',
    baseUrl: inputValues['baseUrl'] as String? ?? '',
    apiKey: inputValues['apiKey'] as String? ?? '',
    modelId: modelId,
  );
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  return const {};
}

List<dynamic> _jsonList(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    if (decoded is List) return decoded;
  }
  return const [];
}

bool _enabled(Object? value) =>
    value == null || value == true || value == 1 || value == '1';
