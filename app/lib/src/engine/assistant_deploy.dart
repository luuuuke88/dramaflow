// 助手逐阶段模型配置（v0.4 spec §4）：o_agentDeploy 表 CRUD（表名/列名不动），
// 只管两个家族基座（见 assistant_stage_registry.dart）。模型必须是 text 类。
import 'dart:convert';

import 'assistant_stage_registry.dart';
import 'engine.dart';
import 'errors.dart';

// DB type 值与旧行保持一致（'agent-stage'），既有部署行无缝复用。
const _assistantDeploymentType = 'agent-stage';

class AssistantDeployment {
  final String key;
  final String name;
  final String fallbackStage;
  final String vendorId;
  final String modelName;
  final int maxOutputTokens;
  final int temperature;
  final bool disabled;
  const AssistantDeployment({
    required this.key,
    required this.name,
    required this.fallbackStage,
    required this.vendorId,
    required this.modelName,
    required this.maxOutputTokens,
    required this.temperature,
    required this.disabled,
  });
}

extension AssistantDeployApi on Engine {
  void _ensureAssistantDeploymentsSeeded() {
    for (final definition in assistantStageDefinitions) {
      final exists = db.select(
        'SELECT id FROM o_agentDeploy WHERE key=? LIMIT 1',
        [definition.key],
      );
      if (exists.isNotEmpty) continue;
      final binding = db.select(
        'SELECT value FROM o_setting WHERE key=?',
        ['binding.${definition.fallbackStage}'],
      ).firstOrNull?['value'] as String?;
      final split = _splitDeployBinding(binding);
      db.execute(
        'INSERT INTO o_agentDeploy '
        '(key,name,desc,type,vendorId,modelName,model,disabled,maxOutputTokens,temperature) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          definition.key,
          definition.name,
          '',
          _assistantDeploymentType,
          split.$1,
          split.$2,
          split.$1.isEmpty || split.$2.isEmpty ? '' : '${split.$1}:${split.$2}',
          0,
          definition.defaultMaxOutputTokens,
          definition.defaultTemperature,
        ],
      );
    }
  }

  List<AssistantDeployment> assistantDeployments() {
    _ensureAssistantDeploymentsSeeded();
    final placeholders =
        List.filled(assistantStageKeys.length, '?').join(',');
    final rows = db
        .select(
          'SELECT key,name,vendorId,modelName,disabled,maxOutputTokens,temperature '
          'FROM o_agentDeploy WHERE key IN ($placeholders)',
          assistantStageKeys,
        )
        .toList()
      ..sort((a, b) =>
          (assistantStageDefinitionByKey[a['key'] as String]?.sortOrder ?? 99)
              .compareTo(assistantStageDefinitionByKey[b['key'] as String]
                      ?.sortOrder ??
                  99));
    return [
      for (final row in rows)
        () {
          final key = row['key'] as String;
          final definition = assistantStageDefinition(key);
          return AssistantDeployment(
            key: key,
            name: row['name'] as String? ?? definition?.name ?? key,
            fallbackStage: definition?.fallbackStage ?? key,
            vendorId: row['vendorId'] as String? ?? '',
            modelName: row['modelName'] as String? ?? '',
            maxOutputTokens: row['maxOutputTokens'] as int? ??
                definition?.defaultMaxOutputTokens ??
                8000,
            temperature: row['temperature'] as int? ??
                definition?.defaultTemperature ??
                70,
            disabled: _deployTruthy(row['disabled']),
          );
        }(),
    ];
  }

  void updateAssistantDeployment(
    String key, {
    String? vendorId,
    String? modelName,
    int? maxOutputTokens,
    int? temperature,
    bool? disabled,
  }) {
    final definition = assistantStageDefinition(key);
    if (definition == null) {
      throw EngineException(errModelMissing, {'stage': key});
    }
    _ensureAssistantDeploymentsSeeded();
    final row = db
        .select('SELECT * FROM o_agentDeploy WHERE key=? LIMIT 1', [key]).first;
    final nextVendor = vendorId ?? row['vendorId'] as String? ?? '';
    final nextModel = modelName ?? row['modelName'] as String? ?? '';
    if (nextVendor.isNotEmpty || nextModel.isNotEmpty) {
      final kind = _assistantModelKind(nextVendor, nextModel);
      if (kind != 'text') {
        throw EngineException(errModelMissing, {
          'stage': key,
          'requiredKind': 'text',
          'actualKind': kind,
        });
      }
    }
    final nextMaxTokens = (maxOutputTokens ??
            row['maxOutputTokens'] as int? ??
            definition.defaultMaxOutputTokens)
        .clamp(256, 64000)
        .toInt();
    final nextTemperature = (temperature ??
            row['temperature'] as int? ??
            definition.defaultTemperature)
        .clamp(0, 200)
        .toInt();
    db.execute(
      'UPDATE o_agentDeploy SET vendorId=?, modelName=?, model=?, disabled=?, '
      'maxOutputTokens=?, temperature=? WHERE key=?',
      [
        nextVendor,
        nextModel,
        nextVendor.isEmpty || nextModel.isEmpty ? '' : '$nextVendor:$nextModel',
        disabled == null ? row['disabled'] as int? ?? 0 : (disabled ? 1 : 0),
        nextMaxTokens,
        nextTemperature,
        key,
      ],
    );
  }

  String _assistantModelKind(String providerId, String modelName) {
    final rows = db.select(
      'SELECT models FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
      [providerId],
    );
    if (rows.isEmpty) {
      throw EngineException(errProviderMissing, {'providerId': providerId});
    }
    final decoded = jsonDecode(rows.first['models'] as String? ?? '[]');
    if (decoded is List) {
      for (final item in decoded.whereType<Map>()) {
        final candidate = Map<String, dynamic>.from(item);
        if (candidate['modelId'] == modelName &&
            (candidate['enabled'] == null ||
                candidate['enabled'] == true ||
                candidate['enabled'] == 1 ||
                candidate['enabled'] == '1')) {
          return candidate['kind'] as String? ?? '';
        }
      }
    }
    throw EngineException(errModelMissing, {'modelId': modelName});
  }
}

(String, String) _splitDeployBinding(String? value) {
  if (value == null) return ('', '');
  final sep = value.indexOf(':');
  if (sep <= 0 || sep == value.length - 1) return ('', '');
  return (value.substring(0, sep), value.substring(sep + 1));
}

bool _deployTruthy(Object? value) =>
    value == true || value == 1 || value == '1' || value == 'true';
