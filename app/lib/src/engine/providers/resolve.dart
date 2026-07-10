import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../assistant_stage_registry.dart';
import '../credentials.dart';
import '../util.dart';

const stageKindByStage = {
  'script_gen': 'text',
  'event_extract': 'text',
  'asset_extract': 'text',
  'storyboard_gen': 'text',
  'video_prompt_gen': 'text',
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
  final int? maxOutputTokens;
  final int? temperature;

  const ResolvedModel({
    required this.providerId,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    this.maxOutputTokens,
    this.temperature,
  });

  ResolvedModel copyWith({
    int? maxOutputTokens,
    int? temperature,
  }) =>
      ResolvedModel(
        providerId: providerId,
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        modelId: modelId,
        maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
        temperature: temperature ?? this.temperature,
      );
}

String requiredKindForStage(String stage) {
  final kind = stageKindByStage[stage];
  if (kind == null) {
    throw EngineException(errModelMissing, {'stage': stage});
  }
  return kind;
}

Future<ResolvedModel> resolveStage(
  Database db,
  CredentialStore credentials,
  String stage,
) async {
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

  return _resolvedModel(
    p,
    inputValues,
    modelId,
    credentials,
  );
}

Future<ResolvedModel> _resolvedModel(
  Row provider,
  Map<String, dynamic> inputValues,
  String modelId,
  CredentialStore credentials,
) async {
  final providerId = provider['id'] as String;
  final credentialRef =
      (inputValues['credentialRef'] as String?)?.trim().isNotEmpty == true
          ? inputValues['credentialRef'] as String
          : providerCredentialRef(providerId);
  final apiKey = await credentials.read(credentialRef);
  if (apiKey == null || apiKey.isEmpty) {
    throw EngineException(errProviderMissing, {
      'providerId': providerId,
      'reason': '未配置 API Key',
    });
  }
  return ResolvedModel(
    providerId: providerId,
    protocol: inputValues['protocol'] as String? ?? 'openai_compatible',
    baseUrl: inputValues['baseUrl'] as String? ?? '',
    apiKey: apiKey,
    modelId: modelId,
  );
}

/// 助手（v0.4 瘦身版）阶段解析：优先 o_agentDeploy 覆盖，否则回退 `binding.<stage>`。
Future<ResolvedModel> resolveAssistantStage(
  Database db,
  CredentialStore credentials,
  String stage,
) async {
  final fallbackStage = assistantStageFallback(stage);
  final rows = db.select(
    'SELECT vendorId,modelName,disabled,maxOutputTokens,temperature '
    'FROM o_agentDeploy WHERE key=? LIMIT 1',
    [stage],
  );
  if (rows.isEmpty || _disabled(rows.first['disabled'])) {
    return resolveStage(db, credentials, fallbackStage);
  }
  final row = rows.first;
  final providerId = (row['vendorId'] as String?)?.trim() ?? '';
  final modelName = (row['modelName'] as String?)?.trim() ?? '';
  if (providerId.isEmpty || modelName.isEmpty) {
    return resolveStage(db, credentials, fallbackStage);
  }
  return (await resolveModelById(db, credentials, providerId, modelName))
      .copyWith(
    maxOutputTokens: row['maxOutputTokens'] as int?,
    temperature: row['temperature'] as int?,
  );
}

/// 按 providerId + modelId 直接解析一个已启用模型（用于逐次生成时覆盖阶段绑定，
/// 对齐 ToonFlow generateAssets/generateFlowImage 的 model 入参）。kind 不限。
Future<ResolvedModel> resolveModelById(
  Database db,
  CredentialStore credentials,
  String providerId,
  String modelId,
) async {
  final providers = db.select(
      'SELECT id, inputValues, models FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
      [providerId]);
  if (providers.isEmpty) {
    throw EngineException(errProviderMissing, {'providerId': providerId});
  }
  final p = providers.first;
  final inputValues = _jsonMap(p['inputValues']);
  final models = _jsonList(p['models']);
  Map<String, dynamic>? model;
  for (final item in models.whereType<Map>()) {
    final c = Map<String, dynamic>.from(item);
    if (c['modelId'] == modelId && _enabled(c['enabled'])) {
      model = c;
      break;
    }
  }
  if (model == null) {
    throw EngineException(errModelMissing, {'modelId': modelId});
  }
  return _resolvedModel(p, inputValues, modelId, credentials);
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

bool _disabled(Object? value) =>
    value == true || value == 1 || value == '1' || value == 'true';
