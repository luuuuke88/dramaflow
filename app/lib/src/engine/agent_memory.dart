import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';

import 'providers/gateway.dart';

const agentMemoryTypeMessage = 'message';
const agentMemoryTypeSummary = 'summary';
const agentMemoryTypeNote = 'note';
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

  const AgentMemorySettings({
    this.messagesPerSummary = 3,
    this.summaryMaxLength = 500,
    this.shortTermLimit = 5,
    this.summaryLimit = 10,
    this.ragLimit = 3,
    this.deepRetrieveSummaryLimit = 5,
    this.rerankEnabled = false,
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

  String embeddingJson(String text);

  Map<String, int> embeddingFromText(String text);

  int score({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
    required String memoryEmbedding,
  });

  List<String> matchedTokens({
    required String name,
    required String content,
    required String query,
    required Set<String> tokens,
  });
}

class TokenAgentMemoryEmbeddingProvider extends AgentMemoryEmbeddingProvider {
  const TokenAgentMemoryEmbeddingProvider();

  @override
  String embeddingJson(String text) =>
      jsonEncode(embeddingFromText(normalizeMemoryText(text)));

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
        embeddingProvider.embeddingJson('$name $trimmed'),
        isolationKey,
        '[]',
        role,
        0,
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
    Set<String>? excludeRoleSuffixes,
    CancelToken? cancelToken,
  }) async {
    final settings = readSettings();
    final normalized = normalizeMemoryText(query);
    final tokens = memorySearchTokens(normalized);
    final queryEmbedding = embeddingProvider.embeddingFromText(normalized);
    final excludedRelatedIdFilter = _normalizeIdFilter(excludeRelatedIds);
    final excludedRoleSuffixFilter = _normalizeRoleFilter(
      excludeRoleSuffixes,
    );
    final rankedMessages = settings.ragLimit <= 0
        ? const <(int, AgentMemoryEntry)>[]
        : _rankMessageCandidates(
            isolationKey: isolationKey,
            normalized: normalized,
            tokens: tokens,
            queryEmbedding: queryEmbedding,
            excludeIds: excludedRelatedIdFilter,
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
      null,
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
      null,
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
    final queryEmbedding = embeddingProvider.embeddingFromText(normalized);
    final noteMatches = allowNotes && noteIsolationKey != null
        ? [
            for (final item in _filterRankedEntries(
              _rankNoteCandidates(
                isolationKey: noteIsolationKey,
                normalized: normalized,
                tokens: tokens,
                queryEmbedding: queryEmbedding,
              ),
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

    final scored = _rankSummaryCandidates(
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
        final directMatches = _rankMessageCandidates(
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
          _rankMessageCandidates(
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
      _rankMessageCandidates(
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
          _withTrace(
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

  AgentMemoryEntry _entryWithProviderEmbedding(
    AgentMemoryEntry entry, {
    required String isolationKey,
  }) {
    final embedding =
        embeddingProvider.embeddingJson('${entry.name} ${entry.content}');
    if (embedding == entry.embedding) return entry;
    db.execute(
      'UPDATE memories SET embedding=? WHERE id=? AND isolationKey=?',
      [embedding, entry.id, isolationKey],
    );
    return entry.copyWith(embedding: embedding);
  }

  List<(int, AgentMemoryEntry)> _rankMessageCandidates({
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
    bool onlyUnsummarized = false,
    Set<String>? excludeIds,
    Set<String>? excludeRoleSuffixes,
  }) {
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
      if (!_matchesExcludedRoleSuffixFilter(entry, excludeRoleSuffixes)) {
        continue;
      }
      entry = _entryWithProviderEmbedding(
        entry,
        isolationKey: isolationKey,
      );
      final score = embeddingProvider.score(
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
            matchedTokens: embeddingProvider.matchedTokens(
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

  List<(int, AgentMemoryEntry)> _rankSummaryCandidates({
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
  }) {
    final summaries = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime DESC, id DESC',
      [isolationKey, agentMemoryTypeSummary],
    );
    final scored = <(int, AgentMemoryEntry)>[];
    for (final row in summaries) {
      final entry = _entryWithProviderEmbedding(
        AgentMemoryEntry.fromRow(row),
        isolationKey: isolationKey,
      );
      final score = embeddingProvider.score(
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
            matchedTokens: embeddingProvider.matchedTokens(
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

  List<(int, AgentMemoryEntry)> _rankNoteCandidates({
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
  }) {
    if (normalized.isEmpty) return const [];
    final notes = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime DESC, id DESC',
      [isolationKey, agentMemoryTypeNote],
    );
    final scored = <(int, AgentMemoryEntry)>[];
    for (final row in notes) {
      final entry = _entryWithProviderEmbedding(
        AgentMemoryEntry.fromRow(row),
        isolationKey: isolationKey,
      );
      final score = embeddingProvider.score(
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
            matchedTokens: embeddingProvider.matchedTokens(
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

  AgentMemoryEntry _withTrace(
    AgentMemoryEntry source, {
    required String isolationKey,
    required String normalized,
    required Set<String> tokens,
    required Map<String, int> queryEmbedding,
  }) {
    final entry = _entryWithProviderEmbedding(
      source,
      isolationKey: isolationKey,
    );
    final score = embeddingProvider.score(
      name: entry.name,
      content: entry.content,
      query: normalized,
      tokens: tokens,
      queryEmbedding: queryEmbedding,
      memoryEmbedding: entry.embedding,
    );
    return entry.copyWith(
      score: score,
      matchedTokens: embeddingProvider.matchedTokens(
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
      );

  Future<void> _summarizeIfNeeded(
    String isolationKey, {
    CancelToken? cancelToken,
  }) async {
    final settings = readSettings();
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
        embeddingProvider.embeddingJson(summary),
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
