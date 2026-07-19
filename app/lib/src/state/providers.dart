import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/models.dart';
import '../engine/engine.dart';
import '../engine/queue.dart';

final engineProvider = Provider<Engine>(
  (_) =>
      throw UnimplementedError('engineProvider must be overridden by main()'),
);

ThemeMode _themeModeFromString(String value) => switch (value) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };

String _themeModeToString(ThemeMode mode) => switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    };

Locale? _localeFromString(String value) => switch (value) {
      'zh' => const Locale('zh'),
      'en' => const Locale('en'),
      'ja' => const Locale('ja'),
      _ => null,
    };

String _localeToString(Locale? locale) {
  final languageCode = locale?.languageCode ?? '';
  return {'zh', 'en', 'ja'}.contains(languageCode) ? languageCode : '';
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    Future.microtask(_load);
    return ThemeMode.light;
  }

  Future<void> _load() async {
    try {
      state =
          _themeModeFromString(await ref.read(engineProvider).getThemeMode());
    } catch (_) {
      state = ThemeMode.light;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final previous = state;
    state = mode;
    try {
      await ref.read(engineProvider).setThemeMode(_themeModeToString(mode));
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    Future.microtask(_load);
    return null;
  }

  Future<void> _load() async {
    try {
      state = _localeFromString(await ref.read(engineProvider).getAppLocale());
    } catch (_) {
      state = null;
    }
  }

  Future<void> setLocale(Locale? locale) async {
    final previous = state;
    state = _localeFromString(_localeToString(locale));
    try {
      await ref.read(engineProvider).setAppLocale(_localeToString(locale));
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

class ActiveJobsNotifier extends Notifier<List<TasksRow>> {
  StreamSubscription<void>? _sub;
  bool _fetching = false;
  bool _again = false;

  @override
  List<TasksRow> build() {
    final engine = ref.watch(engineProvider);
    _sub?.cancel();
    _sub = engine.queue.events.listen((_) => _refresh());
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_refresh);
    return const [];
  }

  Future<void> _refresh() async {
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    try {
      final jobs = await ref.read(engineProvider).activeJobs();
      final oldKey = state.map((job) => '${job.id}:${job.state}').join(',');
      final newKey = jobs.map((job) => '${job.id}:${job.state}').join(',');
      ref.read(jobsGenerationProvider.notifier).bump();
      if (oldKey != newKey) {
        state = jobs;
        WakelockPlus.toggle(enable: jobs.isNotEmpty).catchError((_) {});
      }
    } catch (_) {
      // 保持现状，避免队列刷新错误打断 UI。
    } finally {
      _fetching = false;
      if (_again) {
        _again = false;
        Future.microtask(_refresh);
      }
    }
  }

  void poke() => Future.microtask(_refresh);
}

final activeJobsProvider = NotifierProvider<ActiveJobsNotifier, List<TasksRow>>(
    ActiveJobsNotifier.new);

class JobsGenerationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final jobsGenerationProvider =
    NotifierProvider<JobsGenerationNotifier, int>(JobsGenerationNotifier.new);

final projectsProvider = FutureProvider.autoDispose<List<ProjectRow>>((ref) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).listProjects();
});

final projectJobsProvider =
    FutureProvider.autoDispose.family<List<TasksRow>, int>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).projectJobs(projectId);
});

final settingsProvider = FutureProvider.autoDispose<AppSettings>(
  (ref) => ref.watch(engineProvider).getSettings(),
);

final healthProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(engineProvider).health(),
);

final providersProvider = FutureProvider.autoDispose<List<ProviderInfo>>(
  (ref) => ref.watch(engineProvider).listProviders(),
);

final bindingsProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(engineProvider).getBindings(),
);

final promptsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(engineProvider).listPrompts(),
);

final modelPromptsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(engineProvider).listModelPrompts(),
);

/// 设置页的模型提示词库只显示可实际绑定的图片/视频模型。绑定路径单独保留，
/// 以兼容历史视频模型可能留有多条模式模板的情况。
class ModelPromptTarget {
  final ProviderInfo provider;
  final ProviderModelInfo model;
  final Set<String> boundTemplatePaths;

  const ModelPromptTarget({
    required this.provider,
    required this.model,
    required this.boundTemplatePaths,
  });

  String get key => '${provider.id}:${model.modelId}';
}

final modelPromptTemplatesProvider =
    FutureProvider.autoDispose<List<ModelPromptTemplate>>(
  (ref) => ref.watch(engineProvider).listModelPromptTemplates(),
);

final modelPromptTargetsProvider =
    FutureProvider.autoDispose<List<ModelPromptTarget>>((ref) async {
  final engine = ref.watch(engineProvider);
  final providers = await engine.listProviders();
  final bindings = await engine.listModelPromptBindings();
  final boundPaths = <String, Set<String>>{};
  for (final binding in bindings) {
    boundPaths
        .putIfAbsent('${binding.providerId}:${binding.modelId}', () => {})
        .add(binding.path);
  }

  final targets = <ModelPromptTarget>[];
  for (final provider in providers.where((provider) => provider.enabled)) {
    final models = await engine.listProviderModels(provider.id);
    for (final model in models) {
      if (!model.enabled || (model.kind != 'image' && model.kind != 'video')) {
        continue;
      }
      final key = '${provider.id}:${model.modelId}';
      targets.add(ModelPromptTarget(
        provider: provider,
        model: model,
        boundTemplatePaths: Set.unmodifiable(boundPaths[key] ?? const {}),
      ));
    }
  }
  targets.sort((a, b) {
    final providerOrder = a.provider.name.compareTo(b.provider.name);
    return providerOrder != 0
        ? providerOrder
        : a.model.label.compareTo(b.model.label);
  });
  return targets;
});

/// 当前选中项目（对应 ToonFlow projectStore.currentProject）。
/// 深链/刷新时可用 ensure(pid) 从引擎按 id 回填。
class CurrentProjectNotifier extends Notifier<ProjectRow?> {
  @override
  ProjectRow? build() => null;

  void select(ProjectRow? project) => state = project;

  void ensure(int projectId) {
    if (state?.id == projectId) return;
    try {
      final rows = ref.read(engineProvider).projects();
      for (final p in rows) {
        if (p.id == projectId) {
          state = p;
          return;
        }
      }
    } catch (_) {}
  }

  /// 项目编辑/删除后刷新当前引用。
  void refresh() {
    final id = state?.id;
    if (id == null) return;
    state = null;
    ensure(id);
  }
}

final currentProjectProvider =
    NotifierProvider<CurrentProjectNotifier, ProjectRow?>(
        CurrentProjectNotifier.new);
