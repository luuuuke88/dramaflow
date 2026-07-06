import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';

import 'providers/gateway.dart';

const agentMemoryTypeMessage = 'message';
const agentMemoryTypeSummary = 'summary';
const agentMemoryTypeNote = 'note';
const _agentMemoryToolRole = 'tool';
const agentMemoryScopeAll = 'all';

class AgentMemoryEntry {
  final String id;
  final String name;
  final String content;
  final int createdAt;
  final String embedding;
  final String role;
  final String type;
  final List<String> relatedMessageIds;
  final List<String> sourceSummaryIds;
  final int? score;
  final List<String> matchedTokens;

  const AgentMemoryEntry({
    required this.id,
    required this.name,
    required this.content,
    required this.createdAt,
    required this.embedding,
    required this.role,
    required this.type,
    this.relatedMessageIds = const [],
    this.sourceSummaryIds = const [],
    this.score,
    this.matchedTokens = const [],
  });

  factory AgentMemoryEntry.fromRow(Map<String, Object?> row) =>
      AgentMemoryEntry(
        id: row['id'] as String,
        name: row['name'] as String? ?? '',
        content: row['content'] as String? ?? '',
        createdAt: row['createTime'] as int? ?? 0,
        embedding: row['embedding'] as String? ?? '',
        role: row['role'] as String? ?? '',
        type: row['type'] as String? ?? '',
        relatedMessageIds: _decodeStringList(row['relatedMessageIds']),
      );

  AgentMemoryEntry copyWith({
    String? embedding,
    List<String>? sourceSummaryIds,
    int? score,
    List<String>? matchedTokens,
  }) =>
      AgentMemoryEntry(
        id: id,
        name: name,
        content: content,
        createdAt: createdAt,
        embedding: embedding ?? this.embedding,
        role: role,
        type: type,
        relatedMessageIds: relatedMessageIds,
        sourceSummaryIds: sourceSummaryIds ?? this.sourceSummaryIds,
        score: score ?? this.score,
        matchedTokens: matchedTokens ?? this.matchedTokens,
      );
}

class AgentMemorySettings {
  final int messagesPerSummary;
  final int summaryMaxLength;
  final int shortTermLimit;
  final int summaryLimit;
  final int ragLimit;
  final int deepRetrieveSummaryLimit;
  final bool rerankEnabled;
  final List<String> modelOnnxFile;
  final String modelDtype;

  const AgentMemorySettings({
    this.messagesPerSummary = 3,
    this.summaryMaxLength = 500,
    this.shortTermLimit = 5,
    this.summaryLimit = 10,
    this.ragLimit = 3,
    this.deepRetrieveSummaryLimit = 5,
    this.rerankEnabled = false,
    this.modelOnnxFile = const [
      'all-MiniLM-L6-v2',
      'onnx',
      'model_fp16.onnx',
    ],
    this.modelDtype = 'fp16',
  });
}

class AgentMemoryContext {
  final List<AgentMemoryEntry> relatedMessages;
  final List<AgentMemoryEntry> summaries;
  final List<AgentMemoryEntry> recentMessages;

  const AgentMemoryContext({
    this.relatedMessages = const [],
    this.summaries = const [],
    this.recentMessages = const [],
  });

  bool get isEmpty =>
      relatedMessages.isEmpty && summaries.isEmpty && recentMessages.isEmpty;
}

abstract class AgentMemoryEmbeddingProvider {
  const AgentMemoryEmbeddingProvider();

  FutureOr<String> embeddingJson(String text);

  FutureOr<Map<String, int>> embeddingFromText(String text);

  FutureOr<int> score({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
    required String memoryEmbedding,
  });

  FutureOr<List<String>> matchedTokens({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
  });

  bool shouldRebuildStoredEmbedding(String embedding) => true;
}

class TokenAgentMemoryEmbeddingProvider extends AgentMemoryEmbeddingProvider {
  final List<String> modelOnnxFile;
  final String modelDtype;

  const TokenAgentMemoryEmbeddingProvider({
    this.modelOnnxFile = const [
      'all-MiniLM-L6-v2',
      'onnx',
      'model_fp16.onnx',
    ],
    this.modelDtype = 'fp16',
  });

  @override
  String embeddingJson(String text) => _tokenEmbeddingJsonFromMap(
        embeddingFromText(normalizeMemoryText(text)),
        modelOnnxFile: modelOnnxFile,
        modelDtype: modelDtype,
      );

  @override
  Map<String, int> embeddingFromText(String text) =>
      memoryEmbeddingFromText(text);

  @override
  int score({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
    required String memoryEmbedding,
  }) =>
      memoryScore(
        name,
        content,
        query,
        tokens,
        queryEmbedding,
        memoryEmbedding,
      );

  @override
  List<String> matchedTokens({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
  }) =>
      memoryMatchedTokens(name, content, query, tokens);

  @override
  bool shouldRebuildStoredEmbedding(String embedding) =>
      !_isTokenEmbeddingJsonFor(
        embedding,
        modelOnnxFile: modelOnnxFile,
        modelDtype: modelDtype,
      );
}

class GatewayAgentMemoryEmbeddingProvider extends AgentMemoryEmbeddingProvider {
  final ProviderGateway gateway;
  final String stage;
  final AgentMemoryEmbeddingProvider fallback;

  const GatewayAgentMemoryEmbeddingProvider(
    this.gateway, {
    required this.stage,
    this.fallback = const TokenAgentMemoryEmbeddingProvider(),
  });

  @override
  Future<String> embeddingJson(String text) async =>
      jsonEncode(await embeddingFromText(text));

  @override
  Future<Map<String, int>> embeddingFromText(String text) async {
    try {
      final vector = await (gateway as dynamic).generateEmbedding(
        text,
        stage: stage,
      ) as List<double>;
      final embedding = gatewayEmbeddingFromVector(vector);
      if (embedding.length > 1) return embedding;
    } catch (_) {
      // Remote/vector embedding must never make Agent memory unusable.
    }
    return fallback.embeddingFromText(text);
  }

  @override
  FutureOr<int> score({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
    required String memoryEmbedding,
  }) {
    final memory = _decodeMemoryEmbedding(memoryEmbedding);
    if (_isGatewayEmbeddingMap(queryEmbedding) &&
        _isGatewayEmbeddingMap(memory)) {
      return _gatewayEmbeddingScore(queryEmbedding, memory);
    }
    return fallback.score(
      name: name,
      content: content,
      query: query,
      tokens: tokens,
      queryEmbedding: queryEmbedding,
      memoryEmbedding: memoryEmbedding,
    );
  }

  @override
  FutureOr<List<String>> matchedTokens({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
  }) =>
      fallback.matchedTokens(
        name: name,
        content: content,
        query: query,
        tokens: tokens,
      );

  @override
  bool shouldRebuildStoredEmbedding(String embedding) =>
      !_isGatewayEmbeddingJson(embedding);
}

class AgentMemoryService {
  final Database db;
  final ProviderGateway gateway;
  final String summaryStage;
  final AgentMemoryEmbeddingProvider embeddingProvider;

  const AgentMemoryService(
    this.db,
    this.gateway, {
    required this.summaryStage,
    this.embeddingProvider = const TokenAgentMemoryEmbeddingProvider(),
  });

  Future<String> add({
    required String isolationKey,
    required String role,
    required String content,
    String name = '',
    int? createTime,
    CancelToken? cancelToken,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    final now = createTime ?? DateTime.now().millisecondsSinceEpoch;
    final id = 'agent_msg_${DateTime.now().microsecondsSinceEpoch}';
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        name.trim(),
        trimmed,
        now,
        await embeddingProvider.embeddingJson('$name $trimmed'),
        isolationKey,
        '[]',
        role,
        _isToolAuditRole(role) ? 1 : 0,
        agentMemoryTypeMessage,
      ],
    );
    await _summarizeIfNeeded(isolationKey, cancelToken: cancelToken);
    return id;
  }

  Future<AgentMemoryContext> get({
    required String isolationKey,
    required String query,
    Set<String>? excludeRelatedIds,
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
    CancelToken? cancelToken,
  }) async {
    final settings = readSettings();
    final normalized = normalizeMemoryText(query);
    final tokens = memorySearchTokens(normalized);
    final queryEmbedding =
        await embeddingProvider.embeddingFromText(normalized);
    final excludedRelatedIdFilter = _normalizeIdFilter(excludeRelatedIds);
    final excludedRoleFilter = _normalizeRoleFilter(excludeRoles);
    final excludedRoleSuffixFilter = _normalizeRoleFilter(
      excludeRoleSuffixes,
    );
    final rankedMessages = settings.ragLimit <= 0
        ? const <(int, AgentMemoryEntry)>[]
        : await _rankMessageCandidates(
            isolationKey: isolationKey,
            normalized: normalized,
            tokens: tokens,
            queryEmbedding: queryEmbedding,
            excludeIds: excludedRelatedIdFilter,
            excludeRoles: excludedRoleFilter,
            excludeRoleSuffixes: excludedRoleSuffixFilter,
          );
    final relatedRaw = await _relatedMessagesForQuery(
      query: query,
      settings: settings,
      rankedMessages: rankedMessages,
      cancelToken: cancelToken,
    );
    final summariesDesc = settings.summaryLimit <= 0
        ? const <AgentMemoryEntry>[]
        : [
            for (final row in db.select(
              'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
              'FROM memories WHERE isolationKey=? AND type=? '
              'ORDER BY createTime DESC, id DESC LIMIT ?',
              [isolationKey, agentMemoryTypeSummary, settings.summaryLimit],
            ))
              AgentMemoryEntry.fromRow(row),
          ];
    final summaries = _filterEntries(
      summariesDesc.reversed,
      null,
      null,
      null,
      excludedRoleFilter,
      excludedRoleSuffixFilter,
    );
    final related = _attachSourceSummaries(relatedRaw, summaries);
    final recentDesc = settings.shortTermLimit <= 0
        ? const <AgentMemoryEntry>[]
        : [
            for (final row in db.select(
              'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
              'FROM memories WHERE isolationKey=? AND type=? '
              'AND COALESCE(summarized,0)=0 '
              'ORDER BY createTime DESC, id DESC LIMIT ?',
              [isolationKey, agentMemoryTypeMessage, settings.shortTermLimit],
            ))
              AgentMemoryEntry.fromRow(row),
          ];
    final recent = _filterEntries(
      recentDesc.reversed,
      null,
      null,
      null,
      excludedRoleFilter,
      excludedRoleSuffixFilter,
    );
    return AgentMemoryContext(
      relatedMessages: related,
      summaries: summaries,
      recentMessages: recent,
    );
  }

  Future<List<AgentMemoryEntry>> deepRetrieve({
    required String isolationKey,
    required String keyword,
    Set<String>? roles,
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
    Set<String>? types,
    Set<String>? excludeIds,
    String? noteIsolationKey,
    CancelToken? cancelToken,
  }) async {
    final roleFilter = _normalizeRoleFilter(roles);
    final excludedRoleFilter = _normalizeRoleFilter(excludeRoles);
    final excludedRoleSuffixFilter = _normalizeRoleFilter(
      excludeRoleSuffixes,
    );
    final typeFilter = _normalizeTypeFilter(types);
    final excludedIdFilter = _normalizeIdFilter(excludeIds);
    final allowMessages =
        _matchesTypeFilter(agentMemoryTypeMessage, typeFilter);
    final allowSummaries =
        _matchesTypeFilter(agentMemoryTypeSummary, typeFilter);
    final allowNotes = typeFilter?.contains(agentMemoryTypeNote) == true;
    final explicitSummaries =
        typeFilter?.contains(agentMemoryTypeSummary) == true;
    if (!allowMessages && !allowSummaries && !allowNotes) return const [];
    final settings = readSettings();
    final normalized = normalizeMemoryText(keyword);
    final tokens = memorySearchTokens(normalized);
    final queryEmbedding =
        await embeddingProvider.embeddingFromText(normalized);
    final rankedNotes = allowNotes && noteIsolationKey != null
        ? await _rankNoteCandidates(
            isolationKey: noteIsolationKey,
            normalized: normalized,
            tokens: tokens,
            queryEmbedding: queryEmbedding,
          )
        : const <(int, AgentMemoryEntry)>[];
    final noteMatches = allowNotes && noteIsolationKey != null
        ? [
            for (final item in _filterRankedEntries(
              rankedNotes,
              roleFilter,
              typeFilter,
              excludedIdFilter,
              excludedRoleFilter,
              excludedRoleSuffixFilter,
            ).take(settings.ragLimit))
              item.$2,
          ]
        : const <AgentMemoryEntry>[];
    List<AgentMemoryEntry> withNotes(List<AgentMemoryEntry> entries) =>
        noteMatches.isEmpty ? entries : [...noteMatches, ...entries];
    if (!allowMessages && !allowSummaries) return noteMatches;

    final scored = await _rankSummaryCandidates(
      isolationKey: isolationKey,
      normalized: normalized,
      tokens: tokens,
      queryEmbedding: queryEmbedding,
    );
    final localCandidates = [
      for (final item in scored.take(settings.deepRetrieveSummaryLimit))
        if (_matchesIdFilter(item.$2, excludedIdFilter)) item.$2,
    ];
    final selectedSummaries = await _llmFilterSummaries(
      keyword: keyword,
      candidates: localCandidates,
      cancelToken: cancelToken,
    );
    if (selectedSummaries != null &&
        selectedSummaries.isEmpty &&
        localCandidates.isNotEmpty) {
      return noteMatches;
    }
    final summaries = selectedSummaries ?? localCandidates;

    final ids = <String>[];
    final sourceSummaryIdsByMessageId = <String, List<String>>{};
    for (final summary in summaries) {
      for (final id in summary.relatedMessageIds) {
        if (excludedIdFilter != null && excludedIdFilter.contains(id)) {
          continue;
        }
        if (!ids.contains(id)) ids.add(id);
        (sourceSummaryIdsByMessageId[id] ??= <String>[]).add(summary.id);
      }
    }
    if (ids.isEmpty) {
      if (summaries.isNotEmpty) {
        final directMatches = await _rankMessageCandidates(
          isolationKey: isolationKey,
          normalized: normalized,
          tokens: tokens,
          queryEmbedding: queryEmbedding,
          onlyUnsummarized: true,
        );
        return withNotes([
          ..._filterEntries(
            summaries,
            roleFilter,
            typeFilter,
            excludedIdFilter,
            excludedRoleFilter,
            excludedRoleSuffixFilter,
          ),
          if (allowMessages)
            for (final message in _filterRankedEntries(
              directMatches,
              roleFilter,
              typeFilter,
              excludedIdFilter,
              excludedRoleFilter,
              excludedRoleSuffixFilter,
            ).take(settings.ragLimit))
              message.$2,
        ]);
      }
      if (!allowMessages) return noteMatches;
      return withNotes([
        for (final item in _filterRankedEntries(
          await _rankMessageCandidates(
            isolationKey: isolationKey,
            normalized: normalized,
            tokens: tokens,
            queryEmbedding: queryEmbedding,
            onlyUnsummarized: scored.isNotEmpty,
          ),
          roleFilter,
          typeFilter,
          excludedIdFilter,
          excludedRoleFilter,
          excludedRoleSuffixFilter,
        ).take(settings.ragLimit))
          item.$2,
      ]);
    }
    if (!allowMessages) {
      return withNotes(_filterEntries(
        summaries,
        roleFilter,
        typeFilter,
        excludedIdFilter,
        excludedRoleFilter,
        excludedRoleSuffixFilter,
      ));
    }
    final directMatches = _filterRankedEntries(
      await _rankMessageCandidates(
        isolationKey: isolationKey,
        normalized: normalized,
        tokens: tokens,
        queryEmbedding: queryEmbedding,
        onlyUnsummarized: true,
      ),
      roleFilter,
      typeFilter,
      excludedIdFilter,
      excludedRoleFilter,
      excludedRoleSuffixFilter,
    ).take(settings.ragLimit);
    for (final message in directMatches) {
      if (!ids.contains(message.$2.id)) ids.add(message.$2.id);
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories WHERE isolationKey=? AND type=? AND id IN ($placeholders) '
      'ORDER BY createTime ASC, id ASC',
      [isolationKey, agentMemoryTypeMessage, ...ids],
    );
    final expanded = _filterEntries(
      [
        for (final row in rows)
          await _withTrace(
            AgentMemoryEntry.fromRow(row).copyWith(
              sourceSummaryIds:
                  sourceSummaryIdsByMessageId[row['id'] as String] ?? const [],
            ),
            isolationKey: isolationKey,
            normalized: normalized,
            tokens: tokens,
            queryEmbedding: queryEmbedding,
          ),
      ],
      roleFilter,
      typeFilter,
      excludedIdFilter,
      excludedRoleFilter,
      excludedRoleSuffixFilter,
    );
    if (expanded.isEmpty && summaries.isNotEmpty) {
      return allowSummaries
          ? withNotes(
              _filterEntries(
                summaries,
                roleFilter,
                typeFilter,
                excludedIdFilter,
                excludedRoleFilter,
                excludedRoleSuffixFilter,
              ),
            )
          : noteMatches;
    }
    if (explicitSummaries) {
      return withNotes([
        ..._filterEntries(
          summaries,
          roleFilter,
          typeFilter,
          excludedIdFilter,
          excludedRoleFilter,
          excludedRoleSuffixFilter,
        ),
        ...expanded,
      ]);
    }
    return withNotes(expanded);
  }

  Future<List<AgentMemoryEntry>> searchNotes({
    required String isolationKey,
    required String query,
    int limit = 5,
  }) async {
    if (limit <= 0) return const [];
    final normalized = normalizeMemoryText(query);
    if (normalized.isEmpty) {
      final rows = db.select(
        'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
        'FROM memories WHERE isolationKey=? AND type=? '
        'ORDER BY createTime DESC, id DESC LIMIT ?',
        [isolationKey, agentMemoryTypeNote, limit],
      );
      final entries = <AgentMemoryEntry>[];
      for (final row in rows) {
        final entry = await _entryWithProviderEmbedding(
          AgentMemoryEntry.fromRow(row),
          isolationKey: isolationKey,
        );
        entries.add(entry.copyWith(score: 1, matchedTokens: const []));
      }
      return entries;
    }

    final tokens = memorySearchTokens(normalized);
    final queryEmbedding =
        await embeddingProvider.embeddingFromText(normalized);
    final ranked = await _rankNoteCandidates(
      isolationKey: isolationKey,
      normalized: normalized,
      tokens: tokens,
      queryEmbedding: queryEmbedding,
    );
    return [for (final item in ranked.take(limit)) item.$2];
  }

  void clear({
    required String isolationKey,
    required String scope,
  }) {
    final trimmedScope = scope.trim();
    if (trimmedScope == agentMemoryScopeAll) {
      db.execute('DELETE FROM memories WHERE isolationKey=?', [isolationKey]);
      return;
    }
    const allowedScopes = {
      agentMemoryTypeMessage,
      agentMemoryTypeSummary,
      agentMemoryTypeNote,
    };
    if (!allowedScopes.contains(trimmedScope)) return;
    if (trimmedScope == agentMemoryTypeMessage) {
      db.execute(
        'DELETE FROM memories WHERE isolationKey=? AND type IN (?,?)',
        [isolationKey, agentMemoryTypeMessage, agentMemoryTypeSummary],
      );
      return;
    }
    if (trimmedScope == agentMemoryTypeSummary) {
      db.execute(
        'UPDATE memories SET summarized=0 '
        'WHERE isolationKey=? AND type=? AND summarized=1',
        [isolationKey, agentMemoryTypeMessage],
      );
      db.execute(
        'DELETE FROM memories WHERE isolationKey=? AND type=?',
        [isolationKey, agentMemoryTypeSummary],
      );
      return;
    }
    db.execute(
      'DELETE FROM memories WHERE isolationKey=? AND type=?',
      [isolationKey, trimmedScope],
    );
  }

  Future<List<AgentMemoryEntry>> _relatedMessagesForQuery({
    required String query,
    required AgentMemorySettings settings,
    required List<(int, AgentMemoryEntry)> rankedMessages,
    CancelToken? cancelToken,
  }) async {
    if (settings.ragLimit <= 0 || rankedMessages.isEmpty) return const [];
    final localRelated = [for (final item in rankedMessages) item.$2];
    if (!settings.rerankEnabled) {
      return localRelated.take(settings.ragLimit).toList();
    }
    final candidateLimit = _rerankCandidateLimit(settings);
    final reranked = await _llmRerankMessages(
      query: query,
      candidates: localRelated.take(candidateLimit).toList(),
      cancelToken: cancelToken,
    );
    return (reranked ?? localRelated).take(settings.ragLimit).toList();
  }

  int _rerankCandidateLimit(AgentMemorySettings settings) =>
      (settings.ragLimit * 3).clamp(settings.ragLimit, 20).toInt();

  Future<AgentMemoryEntry> _entryWithProviderEmbedding(
    AgentMemoryEntry entry, {
    required String isolationKey,
  }) async {
    if (entry.embedding.trim().isNotEmpty &&
        !embeddingProvider.shouldRebuildStoredEmbedding(entry.embedding)) {
      return entry;
    }
    final embedding =
        await embeddingProvider.embeddingJson('${entry.name} ${entry.content}');
    if (embedding == entry.embedding) return entry;
    db.execute(
      'UPDATE memories SET embedding=? WHERE id=? AND isolationKey=?',
      [embedding, entry.id, isolationKey],
    );
    return entry.copyWith(embedding: embedding);
  }

  Future<List<(int, AgentMemoryEntry)>> _rankMessageCandidates({
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
    bool onlyUnsummarized = false,
    Set<String>? excludeIds,
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
  }) async {
    if (normalized.isEmpty) return const [];
    final messages = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories WHERE isolationKey=? AND type=? '
      '${onlyUnsummarized ? 'AND summarized=0 ' : ''}'
      'ORDER BY createTime DESC, id DESC',
      [isolationKey, agentMemoryTypeMessage],
    );
    final scored = <(int, AgentMemoryEntry)>[];
    for (final row in messages) {
      var entry = AgentMemoryEntry.fromRow(row);
      if (excludeIds != null && excludeIds.contains(entry.id)) continue;
      if (!_matchesExcludedRoleFilter(entry, excludeRoles)) continue;
      if (!_matchesExcludedRoleSuffixFilter(entry, excludeRoleSuffixes)) {
        continue;
      }
      entry = await _entryWithProviderEmbedding(
        entry,
        isolationKey: isolationKey,
      );
      final score = await embeddingProvider.score(
        name: entry.name,
        content: entry.content,
        query: normalized,
        tokens: tokens,
        queryEmbedding: queryEmbedding,
        memoryEmbedding: entry.embedding,
      );
      if (score > 0) {
        scored.add((
          score,
          entry.copyWith(
            score: score,
            matchedTokens: await embeddingProvider.matchedTokens(
              name: entry.name,
              content: entry.content,
              query: normalized,
              tokens: tokens,
            ),
          ),
        ));
      }
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.createdAt.compareTo(a.$2.createdAt);
    });
    return scored;
  }

  List<AgentMemoryEntry> _attachSourceSummaries(
    List<AgentMemoryEntry> messages,
    List<AgentMemoryEntry> summaries,
  ) {
    if (messages.isEmpty || summaries.isEmpty) return messages;
    final summaryIdsByMessageId = <String, List<String>>{};
    for (final summary in summaries) {
      for (final messageId in summary.relatedMessageIds) {
        (summaryIdsByMessageId[messageId] ??= <String>[]).add(summary.id);
      }
    }
    return [
      for (final message in messages)
        message.copyWith(
          sourceSummaryIds: summaryIdsByMessageId[message.id] ?? const [],
        ),
    ];
  }

  Future<List<(int, AgentMemoryEntry)>> _rankSummaryCandidates({
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
  }) async {
    final summaries = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime DESC, id DESC',
      [isolationKey, agentMemoryTypeSummary],
    );
    final scored = <(int, AgentMemoryEntry)>[];
    for (final row in summaries) {
      final entry = await _entryWithProviderEmbedding(
        AgentMemoryEntry.fromRow(row),
        isolationKey: isolationKey,
      );
      final score = await embeddingProvider.score(
        name: entry.name,
        content: entry.content,
        query: normalized,
        tokens: tokens,
        queryEmbedding: queryEmbedding,
        memoryEmbedding: entry.embedding,
      );
      if (score > 0) {
        scored.add((
          score,
          entry.copyWith(
            score: score,
            matchedTokens: await embeddingProvider.matchedTokens(
              name: entry.name,
              content: entry.content,
              query: normalized,
              tokens: tokens,
            ),
          ),
        ));
      }
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.createdAt.compareTo(a.$2.createdAt);
    });
    return scored;
  }

  Future<List<(int, AgentMemoryEntry)>> _rankNoteCandidates({
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
  }) async {
    if (normalized.isEmpty) return const [];
    final notes = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime DESC, id DESC',
      [isolationKey, agentMemoryTypeNote],
    );
    final scored = <(int, AgentMemoryEntry)>[];
    for (final row in notes) {
      final entry = await _entryWithProviderEmbedding(
        AgentMemoryEntry.fromRow(row),
        isolationKey: isolationKey,
      );
      final score = await embeddingProvider.score(
        name: entry.name,
        content: entry.content,
        query: normalized,
        tokens: tokens,
        queryEmbedding: queryEmbedding,
        memoryEmbedding: entry.embedding,
      );
      if (score > 0) {
        scored.add((
          score,
          entry.copyWith(
            score: score,
            matchedTokens: await embeddingProvider.matchedTokens(
              name: entry.name,
              content: entry.content,
              query: normalized,
              tokens: tokens,
            ),
          ),
        ));
      }
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.createdAt.compareTo(a.$2.createdAt);
    });
    return scored;
  }

  Future<AgentMemoryEntry> _withTrace(
    AgentMemoryEntry source, {
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
  }) async {
    final entry = await _entryWithProviderEmbedding(
      source,
      isolationKey: isolationKey,
    );
    final score = await embeddingProvider.score(
      name: entry.name,
      content: entry.content,
      query: normalized,
      tokens: tokens,
      queryEmbedding: queryEmbedding,
      memoryEmbedding: entry.embedding,
    );
    return entry.copyWith(
      score: score,
      matchedTokens: await embeddingProvider.matchedTokens(
        name: entry.name,
        content: entry.content,
        query: normalized,
        tokens: tokens,
      ),
    );
  }

  Set<String>? _normalizeRoleFilter(Set<String>? roles) {
    if (roles == null) return null;
    final normalized = {
      for (final role in roles)
        if (role.trim().isNotEmpty) role.trim(),
    };
    return normalized.isEmpty ? null : normalized;
  }

  Set<String>? _normalizeTypeFilter(Set<String>? types) {
    if (types == null) return null;
    final normalized = {
      for (final type in types)
        if (_normalizeMemoryType(type) != null) _normalizeMemoryType(type)!,
    };
    return normalized;
  }

  String? _normalizeMemoryType(String type) {
    final value = type.trim().toLowerCase();
    return switch (value) {
      'message' ||
      'messages' ||
      'chat' ||
      'conversation' =>
        agentMemoryTypeMessage,
      'summary' || 'summaries' => agentMemoryTypeSummary,
      'note' ||
      'notes' ||
      'long_term' ||
      'long-term' ||
      'longterm' =>
        agentMemoryTypeNote,
      _ => null,
    };
  }

  Set<String>? _normalizeIdFilter(Set<String>? ids) {
    if (ids == null) return null;
    final normalized = {
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    };
    return normalized.isEmpty ? null : normalized;
  }

  bool _matchesRoleFilter(AgentMemoryEntry entry, Set<String>? roles) =>
      roles == null || roles.contains(entry.role);

  bool _matchesExcludedRoleFilter(
    AgentMemoryEntry entry,
    Set<String>? roles,
  ) =>
      roles == null || !roles.contains(entry.role);

  bool _matchesExcludedRoleSuffixFilter(
    AgentMemoryEntry entry,
    Set<String>? roleSuffixes,
  ) =>
      roleSuffixes == null ||
      roleSuffixes.every((suffix) => !entry.role.endsWith(suffix));

  bool _matchesTypeFilter(String type, Set<String>? types) =>
      types == null || types.contains(type);

  bool _matchesIdFilter(AgentMemoryEntry entry, Set<String>? excludeIds) =>
      excludeIds == null || !excludeIds.contains(entry.id);

  bool _matchesEntryFilter(
    AgentMemoryEntry entry,
    Set<String>? roles,
    Set<String>? types,
    Set<String>? excludeIds, [
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
  ]) =>
      _matchesRoleFilter(entry, roles) &&
      _matchesExcludedRoleFilter(entry, excludeRoles) &&
      _matchesExcludedRoleSuffixFilter(entry, excludeRoleSuffixes) &&
      _matchesTypeFilter(entry.type, types) &&
      _matchesIdFilter(entry, excludeIds);

  List<AgentMemoryEntry> _filterEntries(
    Iterable<AgentMemoryEntry> entries,
    Set<String>? roles,
    Set<String>? types,
    Set<String>? excludeIds, [
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
  ]) =>
      [
        for (final entry in entries)
          if (_matchesEntryFilter(
            entry,
            roles,
            types,
            excludeIds,
            excludeRoles,
            excludeRoleSuffixes,
          ))
            entry
      ];

  Iterable<(int, AgentMemoryEntry)> _filterRankedEntries(
    Iterable<(int, AgentMemoryEntry)> entries,
    Set<String>? roles,
    Set<String>? types,
    Set<String>? excludeIds, [
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
  ]) sync* {
    for (final item in entries) {
      if (_matchesEntryFilter(
        item.$2,
        roles,
        types,
        excludeIds,
        excludeRoles,
        excludeRoleSuffixes,
      )) {
        yield item;
      }
    }
  }

  Future<List<AgentMemoryEntry>?> _llmFilterSummaries({
    required String keyword,
    required List<AgentMemoryEntry> candidates,
    CancelToken? cancelToken,
  }) async {
    if (candidates.isEmpty) return const [];
    try {
      final result = await gateway.generateText(
        '你是短剧 Agent 的 deepRetrieve 记忆判别器。'
        '请从候选历史摘要中选择与检索关键词真正相关的摘要 id。'
        '只返回 JSON 字符串数组，例如 ["summary_1"]；不相关则返回 []。',
        [
          '检索关键词：$keyword',
          '',
          '候选摘要：',
          for (final candidate in candidates)
            jsonEncode({
              'id': candidate.id,
              'name': candidate.name,
              'content': candidate.content,
            }),
        ].join('\n'),
        stage: summaryStage,
        cancelToken: cancelToken,
      );
      final ids = _parseSelectedSummaryIds(result.content, candidates);
      if (ids == null) return null;
      if (ids.isEmpty) return const [];
      final byId = {
        for (final candidate in candidates) candidate.id: candidate
      };
      return [
        for (final candidate in candidates)
          if (ids.contains(candidate.id) && byId.containsKey(candidate.id))
            candidate,
      ];
    } catch (_) {
      return null;
    }
  }

  Future<List<AgentMemoryEntry>?> _llmRerankMessages({
    required String query,
    required List<AgentMemoryEntry> candidates,
    CancelToken? cancelToken,
  }) async {
    if (candidates.isEmpty) return const [];
    try {
      final result = await gateway.generateText(
        '你是短剧 Agent 的 RAG 记忆重排器。'
        '请从候选原始对话记忆中选择与当前问题真正相关的 message id，按相关性从高到低排序。'
        '只返回 JSON 字符串数组，例如 ["msg_1"]；不相关则返回 []。',
        [
          '当前问题：$query',
          '',
          '候选原始对话：',
          for (final candidate in candidates)
            jsonEncode({
              'id': candidate.id,
              'role': candidate.role,
              'content': candidate.content,
            }),
        ].join('\n'),
        stage: summaryStage,
        cancelToken: cancelToken,
      );
      final ids = _parseSelectedMemoryIds(result.content, candidates);
      if (ids == null) return null;
      if (ids.isEmpty) return const [];
      final byId = {
        for (final candidate in candidates) candidate.id: candidate
      };
      return [
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ];
    } catch (_) {
      return null;
    }
  }

  AgentMemorySettings readSettings() => AgentMemorySettings(
        messagesPerSummary: _intSetting(
          'agent.memory.messagesPerSummary',
          legacyKey: 'messagesPerSummary',
          defaultValue: 3,
          min: 1,
          max: 50,
        ),
        summaryMaxLength: _intSetting(
          'agent.memory.summaryMaxLength',
          legacyKey: 'summaryMaxLength',
          defaultValue: 500,
          min: 80,
          max: 4000,
        ),
        shortTermLimit: _intSetting(
          'agent.memory.shortTermLimit',
          legacyKey: 'shortTermLimit',
          defaultValue: 5,
          min: 0,
          max: 100,
        ),
        summaryLimit: _intSetting(
          'agent.memory.summaryLimit',
          legacyKey: 'summaryLimit',
          defaultValue: 10,
          min: 0,
          max: 100,
        ),
        ragLimit: _intSetting(
          'agent.memory.ragLimit',
          legacyKey: 'ragLimit',
          defaultValue: 3,
          min: 0,
          max: 50,
        ),
        deepRetrieveSummaryLimit: _intSetting(
          'agent.memory.deepRetrieveSummaryLimit',
          legacyKey: 'deepRetrieveSummaryLimit',
          defaultValue: 5,
          min: 0,
          max: 50,
        ),
        rerankEnabled: _boolSetting(
          'agent.memory.rerankEnabled',
          legacyKey: 'rerankEnabled',
          defaultValue: false,
        ),
        modelOnnxFile: _stringListSetting(
          'agent.memory.modelOnnxFile',
          legacyKey: 'modelOnnxFile',
          defaultValue: const [
            'all-MiniLM-L6-v2',
            'onnx',
            'model_fp16.onnx',
          ],
        ),
        modelDtype: _stringSetting(
          'agent.memory.modelDtype',
          legacyKey: 'modelDtype',
          defaultValue: 'fp16',
        ),
      );

  Future<void> _summarizeIfNeeded(
    String isolationKey, {
    CancelToken? cancelToken,
  }) async {
    final settings = readSettings();
    _markToolAuditMessagesSummarized(isolationKey);
    final rows = db.select(
      'SELECT id,role,content,createTime FROM memories '
      'WHERE isolationKey=? AND type=? AND COALESCE(summarized,0)=0 '
      'ORDER BY createTime ASC, id ASC LIMIT ?',
      [
        isolationKey,
        agentMemoryTypeMessage,
        settings.messagesPerSummary,
      ],
    );
    if (rows.length < settings.messagesPerSummary) return;

    final source = [
      for (final row in rows)
        '${row['role'] as String? ?? ''}: ${row['content'] as String? ?? ''}',
    ].join('\n');
    final result = await gateway.generateText(
      '你是短剧 Agent 的记忆摘要器。请把对话压缩为不超过 ${settings.summaryMaxLength} 字的中文摘要。',
      source,
      stage: summaryStage,
      cancelToken: cancelToken,
    );
    var summary = result.content.trim();
    if (summary.length > settings.summaryMaxLength) {
      summary = summary.substring(0, settings.summaryMaxLength);
    }
    if (summary.isEmpty) summary = _fallbackSummary(source, settings);

    final ids = [for (final row in rows) row['id'] as String];
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'agent_sum_${DateTime.now().microsecondsSinceEpoch}',
        '对话摘要',
        summary,
        now,
        await embeddingProvider.embeddingJson(summary),
        isolationKey,
        jsonEncode(ids),
        'assistant',
        0,
        agentMemoryTypeSummary,
      ],
    );
    final placeholders = List.filled(ids.length, '?').join(',');
    db.execute(
      'UPDATE memories SET summarized=1 WHERE isolationKey=? AND type=? AND id IN ($placeholders)',
      [isolationKey, agentMemoryTypeMessage, ...ids],
    );
  }

  void _markToolAuditMessagesSummarized(String isolationKey) {
    db.execute(
      'UPDATE memories SET summarized=1 '
      'WHERE isolationKey=? AND type=? AND COALESCE(summarized,0)=0 '
      'AND (role=? OR role LIKE ?)',
      [
        isolationKey,
        agentMemoryTypeMessage,
        _agentMemoryToolRole,
        '%:tool',
      ],
    );
  }

  bool _isToolAuditRole(String role) {
    final normalized = role.trim();
    return normalized == _agentMemoryToolRole || normalized.endsWith(':tool');
  }

  String _fallbackSummary(String source, AgentMemorySettings settings) {
    final compact = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= settings.summaryMaxLength) return compact;
    return compact.substring(0, settings.summaryMaxLength);
  }

  int _intSetting(
    String key, {
    required String legacyKey,
    required int defaultValue,
    required int min,
    required int max,
  }) {
    final value = db.select('SELECT value FROM o_setting WHERE key=?',
            [key]).firstOrNull?['value'] as String? ??
        db.select('SELECT value FROM o_setting WHERE key=?',
            [legacyKey]).firstOrNull?['value'] as String?;
    final parsed = int.tryParse(value ?? '');
    return (parsed ?? defaultValue).clamp(min, max).toInt();
  }

  bool _boolSetting(
    String key, {
    required String legacyKey,
    required bool defaultValue,
  }) {
    final value = db.select('SELECT value FROM o_setting WHERE key=?',
            [key]).firstOrNull?['value'] as String? ??
        db.select('SELECT value FROM o_setting WHERE key=?',
            [legacyKey]).firstOrNull?['value'] as String?;
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return defaultValue;
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  String _stringSetting(
    String key, {
    required String legacyKey,
    required String defaultValue,
  }) {
    final value = db.select('SELECT value FROM o_setting WHERE key=?',
            [key]).firstOrNull?['value'] as String? ??
        db.select('SELECT value FROM o_setting WHERE key=?',
            [legacyKey]).firstOrNull?['value'] as String?;
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? defaultValue : trimmed;
  }

  List<String> _stringListSetting(
    String key, {
    required String legacyKey,
    required List<String> defaultValue,
  }) {
    final value = _stringSetting(key, legacyKey: legacyKey, defaultValue: '');
    if (value.isEmpty) return defaultValue;
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        final parts = [
          for (final item in decoded)
            if ('$item'.trim().isNotEmpty) '$item'.trim(),
        ];
        if (parts.isNotEmpty) return parts;
      }
    } catch (_) {
      // Fall through to path-like parsing for user-entered compatibility values.
    }
    final parts = value
        .split(RegExp(r'[\\/,\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? defaultValue : parts;
  }
}

String normalizeMemoryText(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

Set<String> memorySearchTokens(String query) {
  if (query.isEmpty) return const {};
  final tokens = <String>{};
  for (final part in query.split(' ')) {
    if (part.isNotEmpty) tokens.add(part);
  }
  final compact = query.replaceAll(' ', '');
  if (compact.length <= 12 && compact.isNotEmpty) tokens.add(compact);
  for (var i = 0; i < compact.length - 1; i++) {
    tokens.add(compact.substring(i, i + 2));
  }
  return tokens;
}

String embeddingJson(String text) =>
    jsonEncode(memoryEmbeddingFromText(normalizeMemoryText(text)));

const _tokenEmbeddingMarker = '__token_embedding_v1';
const _gatewayEmbeddingMarker = '__gateway_embedding_v1';
const _gatewayEmbeddingScale = 1000000;

String tokenEmbeddingJson(
  String text, {
  required List<String> modelOnnxFile,
  required String modelDtype,
}) =>
    _tokenEmbeddingJsonFromMap(
      memoryEmbeddingFromText(normalizeMemoryText(text)),
      modelOnnxFile: modelOnnxFile,
      modelDtype: modelDtype,
    );

String _tokenEmbeddingJsonFromMap(
  Map<String, int> embedding, {
  required List<String> modelOnnxFile,
  required String modelDtype,
}) =>
    jsonEncode({
      _tokenEmbeddingMarker: 1,
      'modelOnnxFile': [
        for (final part in modelOnnxFile)
          if (part.trim().isNotEmpty) part.trim(),
      ],
      'modelDtype': modelDtype.trim(),
      'embedding': embedding,
    });

Map<String, int> gatewayEmbeddingFromVector(List<double> vector) {
  final embedding = <String, int>{_gatewayEmbeddingMarker: 1};
  for (var i = 0; i < vector.length; i++) {
    final value = vector[i];
    if (!value.isFinite) continue;
    final scaled = (value * _gatewayEmbeddingScale).round();
    if (scaled != 0) embedding['d$i'] = scaled;
  }
  return embedding;
}

Map<String, int> memoryEmbeddingFromText(String text) {
  final tokens = memorySearchTokens(text);
  final embedding = <String, int>{};
  for (final token in tokens) {
    if (token.length <= 1) continue;
    embedding[token] = (embedding[token] ?? 0) + 1;
  }
  return Map.fromEntries(
    embedding.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

bool _isGatewayEmbeddingJson(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map && decoded[_gatewayEmbeddingMarker] == 1;
  } catch (_) {
    return false;
  }
}

bool _isGatewayEmbeddingMap(Map<String, int> value) =>
    value[_gatewayEmbeddingMarker] == 1;

bool _isTokenEmbeddingJsonFor(
  String value, {
  required List<String> modelOnnxFile,
  required String modelDtype,
}) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map || decoded[_tokenEmbeddingMarker] != 1) {
      return false;
    }
    final embedded = decoded['embedding'];
    if (embedded is! Map) return false;
    final storedModel = decoded['modelOnnxFile'];
    final storedModelParts = storedModel is List
        ? [
            for (final item in storedModel)
              if ('$item'.trim().isNotEmpty) '$item'.trim(),
          ]
        : const <String>[];
    final expectedModelParts = [
      for (final part in modelOnnxFile)
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (storedModelParts.length != expectedModelParts.length) return false;
    for (var i = 0; i < expectedModelParts.length; i++) {
      if (storedModelParts[i] != expectedModelParts[i]) return false;
    }
    return (decoded['modelDtype'] as String?)?.trim() == modelDtype.trim();
  } catch (_) {
    return false;
  }
}

int _gatewayEmbeddingScore(
  Map<String, int> query,
  Map<String, int> memory,
) {
  var dot = 0.0;
  var queryNorm = 0.0;
  var memoryNorm = 0.0;
  for (final entry in query.entries) {
    if (!entry.key.startsWith('d')) continue;
    final q = entry.value / _gatewayEmbeddingScale;
    queryNorm += q * q;
    final mValue = memory[entry.key];
    if (mValue == null) continue;
    dot += q * (mValue / _gatewayEmbeddingScale);
  }
  for (final entry in memory.entries) {
    if (!entry.key.startsWith('d')) continue;
    final m = entry.value / _gatewayEmbeddingScale;
    memoryNorm += m * m;
  }
  if (dot <= 0 || queryNorm <= 0 || memoryNorm <= 0) return 0;
  final cosine = dot / (math.sqrt(queryNorm) * math.sqrt(memoryNorm));
  return (cosine * _gatewayEmbeddingScale).round();
}

int memoryScore(
  String name,
  String content,
  String query,
  Set<String> tokens,
  Map<String, int> queryEmbedding,
  String embedding,
) {
  if (query.isEmpty) return 1;
  final haystack = normalizeMemoryText('$name\n$content');
  var score = haystack.contains(query) ? 100 : 0;
  for (final token in tokens) {
    if (token.length <= 1) continue;
    if (haystack.contains(token)) score += 10;
  }
  score += _embeddingScore(queryEmbedding, _decodeMemoryEmbedding(embedding));
  return score;
}

List<String> memoryMatchedTokens(
  String name,
  String content,
  String query,
  Set<String> tokens,
) {
  final haystack = normalizeMemoryText('$name\n$content');
  final matched = <String>[];
  void add(String value) {
    final token = value.trim();
    if (token.length <= 1 || matched.contains(token)) return;
    if (haystack.contains(token)) matched.add(token);
  }

  if (query.isNotEmpty) add(query);
  for (final token in tokens) {
    add(token);
  }
  return matched;
}

int _embeddingScore(Map<String, int> query, Map<String, int> memory) {
  var score = 0;
  for (final entry in query.entries) {
    final value = memory[entry.key];
    if (value == null) continue;
    score += entry.value < value ? entry.value : value;
  }
  return score;
}

Map<String, int> _decodeMemoryEmbedding(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return const {};
    if (decoded[_tokenEmbeddingMarker] == 1 && decoded['embedding'] is Map) {
      final embedding = decoded['embedding'] as Map;
      return {
        for (final entry in embedding.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      };
    }
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  } catch (_) {
    return const {};
  }
}

Set<String>? _parseSelectedSummaryIds(
  String source,
  List<AgentMemoryEntry> candidates,
) {
  final allowed = {for (final candidate in candidates) candidate.id};
  final selected = <String>{};
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      for (final item in decoded) {
        final id = '$item'.trim();
        if (allowed.contains(id)) selected.add(id);
      }
      return selected;
    }
    if (decoded is Map) {
      final ids = decoded['ids'] ??
          decoded['summaryIds'] ??
          decoded['summary_ids'] ??
          decoded['relevantSummaryIds'] ??
          decoded['relevant_summary_ids'] ??
          decoded['selected'];
      if (ids is List) {
        for (final item in ids) {
          final id = '$item'.trim();
          if (allowed.contains(id)) selected.add(id);
        }
        return selected;
      }
      return null;
    }
  } catch (_) {
    // Fall through to tolerant id matching for model responses with prose.
  }
  for (final id in allowed) {
    if (trimmed.contains(id)) selected.add(id);
  }
  return selected.isEmpty ? null : selected;
}

List<String>? _parseSelectedMemoryIds(
  String source,
  List<AgentMemoryEntry> candidates,
) {
  final allowed = {for (final candidate in candidates) candidate.id};
  final selected = <String>[];
  final seen = <String>{};
  void addId(Object? value) {
    final id = '$value'.trim();
    if (allowed.contains(id) && seen.add(id)) selected.add(id);
  }

  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      for (final item in decoded) {
        addId(item);
      }
      return selected;
    }
    if (decoded is Map) {
      final ids = decoded['ids'] ??
          decoded['messageIds'] ??
          decoded['message_ids'] ??
          decoded['memoryIds'] ??
          decoded['memory_ids'] ??
          decoded['relevantMessageIds'] ??
          decoded['relevant_message_ids'] ??
          decoded['relevantMemoryIds'] ??
          decoded['relevant_memory_ids'] ??
          decoded['selected'];
      if (ids is List) {
        for (final item in ids) {
          addId(item);
        }
        return selected;
      }
      return null;
    }
  } catch (_) {
    // Fall through to tolerant id matching for model responses with prose.
  }
  for (final id in allowed) {
    if (trimmed.contains(id)) addId(id);
  }
  return selected.isEmpty ? null : selected;
}

List<String> _decodeStringList(Object? value) {
  if (value is! String || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item != null) item.toString(),
    ];
  } catch (_) {
    return const [];
  }
}
