import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'engine.dart';
import 'errors.dart';
import 'manuals.dart';

class PromptSource {
  final String id;
  final String kind;
  final String version;
  final String content;

  const PromptSource({
    required this.id,
    required this.kind,
    required this.version,
    required this.content,
  });

  Map<String, String> toTaskJson() => {
        'id': id,
        'kind': kind,
        'version': version,
      };
}

class PromptResolution {
  final String system;
  final List<PromptSource> sources;

  const PromptResolution({required this.system, required this.sources});

  Map<String, Object?> toTaskJson() => {
        'promptSources': [for (final source in sources) source.toTaskJson()],
      };
}

String promptContentHash(String content) =>
    sha256.convert(utf8.encode(content)).toString();

extension PromptResolverApi on Engine {
  PromptResolution resolvePrompt({
    required int projectId,
    required String basePromptKey,
    String? visualSection,
    String? directorSection,
    String? modelStage,
    String? modelPromptPath,
  }) {
    final projectRows = db.select(
      'SELECT artStyle,directorManual FROM o_project WHERE id=? LIMIT 1',
      [projectId],
    );
    if (projectRows.isEmpty) {
      throw EngineException(errPromptMissing, {'type': 'project:$projectId'});
    }
    final project = projectRows.first;
    final sources = <PromptSource>[];

    void addSource(String id, String kind, String content) {
      if (content.trim().isEmpty) return;
      sources.add(PromptSource(
        id: id,
        kind: kind,
        version: promptContentHash(content),
        content: content,
      ));
    }

    final baseRows = db.select(
      'SELECT useData,data FROM o_prompt WHERE name=? LIMIT 1',
      [basePromptKey],
    );
    if (baseRows.isEmpty) {
      throw EngineException(errPromptMissing, {'type': basePromptKey});
    }
    final baseOverride = baseRows.first['useData'];
    final baseContent = baseOverride is String && baseOverride.isNotEmpty
        ? baseOverride
        : (baseRows.first['data'] as String? ?? '');
    addSource('base:$basePromptKey', 'base', baseContent);

    if (visualSection != null) {
      final pack = (project['artStyle'] as String? ?? '').trim();
      final content = _manualSection(
        visualManuals(),
        kind: 'visual',
        pack: pack,
        section: visualSection,
      );
      addSource('visual:$pack:$visualSection', 'visual', content);
    }

    if (directorSection != null) {
      final pack = (project['directorManual'] as String? ?? '').trim();
      final content = _manualSection(
        directorManuals(),
        kind: 'director',
        pack: pack,
        section: directorSection,
      );
      addSource('director:$pack:$directorSection', 'director', content);
    }

    if (modelPromptPath != null) {
      final stage = modelStage?.trim() ?? '';
      final binding = stage.isEmpty
          ? ''
          : (db.select(
                    'SELECT value FROM o_setting WHERE key=? LIMIT 1',
                    ['binding.$stage'],
                  ).firstOrNull?['value'] as String? ??
                  '')
              .trim();
      final separator = binding.indexOf(':');
      if (separator <= 0 || separator == binding.length - 1) {
        throw EngineException(
          errPromptMissing,
          {'type': 'model:$stage:$modelPromptPath'},
        );
      }
      final providerId = binding.substring(0, separator);
      final modelId = binding.substring(separator + 1);
      final rows = db.select(
        'SELECT prompt FROM o_modelPrompt '
        'WHERE vendorId=? AND model=? AND path=? LIMIT 1',
        [providerId, modelId, modelPromptPath],
      );
      final content = rows.firstOrNull?['prompt'] as String? ?? '';
      if (content.trim().isEmpty) {
        throw EngineException(
          errPromptMissing,
          {'type': 'model:$providerId:$modelId:$modelPromptPath'},
        );
      }
      addSource(
        'model:$providerId:$modelId:$modelPromptPath',
        'model',
        content,
      );
    }

    return PromptResolution(
      system: sources.map((source) => source.content).join('\n\n'),
      sources: List.unmodifiable(sources),
    );
  }
}

String _manualSection(
  List<ManualPack> packs, {
  required String kind,
  required String pack,
  required String section,
}) {
  ManualPack? selected;
  for (final candidate in packs) {
    if (candidate.pack == pack) {
      selected = candidate;
      break;
    }
  }
  final content = selected?.data[section] ?? '';
  if (content.trim().isEmpty) {
    throw EngineException(
      errPromptMissing,
      {'type': '$kind:$pack:$section'},
    );
  }
  return content;
}
