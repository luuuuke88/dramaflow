import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../api/models.dart';
import '../engine/engine.dart';

/// App 级引擎单例：main() 经 overrideWithValue 注入（M0 生命周期约定——
/// 引擎不挂在可重建的 Provider 上，这里只持引用）。
final engineProvider = Provider<Engine>(
    (_) => throw UnimplementedError('engineProvider 由 main() 注入'));

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

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    Future.microtask(_load);
    return ThemeMode.light;
  }

  Future<void> _load() async {
    try {
      final value = await ref.read(engineProvider).getThemeMode();
      state = _themeModeFromString(value);
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

/// 活跃任务监听：订阅引擎队列事件流（取代 v0.1 的 HTTP 轮询）。
/// 事件到达即拉取活跃任务并 bump jobsGeneration；活跃任务存在时保持屏幕常亮
///（对策移动端后台冻结，spec M0 约定）。
class ActiveJobsNotifier extends Notifier<List<Job>> {
  StreamSubscription<void>? _sub;
  bool _fetching = false;
  bool _again = false;

  @override
  List<Job> build() {
    final engine = ref.watch(engineProvider);
    _sub?.cancel();
    _sub = engine.queue.events.listen((_) => _refresh());
    ref.onDispose(() {
      _sub?.cancel();
    });
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
      final oldKey = state.map((j) => '${j.id}:${j.state}').join(',');
      final newKey = jobs.map((j) => '${j.id}:${j.state}').join(',');
      ref.read(jobsGenerationProvider.notifier).bump();
      if (oldKey != newKey) {
        state = jobs;
        _updateWakelock(jobs.isNotEmpty);
      }
    } catch (_) {
      // 引擎侧异常：保持现状
    } finally {
      _fetching = false;
      if (_again) {
        _again = false;
        Future.microtask(_refresh);
      }
    }
  }

  void _updateWakelock(bool active) {
    // Web/测试环境下 wakelock 不可用，静默忽略
    WakelockPlus.toggle(enable: active).catchError((_) {});
  }

  /// 兼容旧签名：发起动作后立即刷新一次
  void poke() => Future.microtask(_refresh);
}

final activeJobsProvider =
    NotifierProvider<ActiveJobsNotifier, List<Job>>(ActiveJobsNotifier.new);

/// 数据刷新信号：任务集合每次变化 +1，数据 Provider watch 它自动重取。
class JobsGenerationNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final jobsGenerationProvider =
    NotifierProvider<JobsGenerationNotifier, int>(JobsGenerationNotifier.new);

// ---------- 数据 Providers（跟随 jobsGeneration 自动刷新） ----------

final projectsProvider = FutureProvider.autoDispose<List<Project>>((ref) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).listProjects();
});

final projectProvider =
    FutureProvider.autoDispose.family<Project, String>((ref, id) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).getProject(id);
});

final novelProvider =
    FutureProvider.autoDispose.family<Novel?, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).getNovel(projectId);
});

final episodesProvider = FutureProvider.autoDispose
    .family<List<EpisodeSummary>, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).listEpisodes(projectId);
});

final episodeProvider =
    FutureProvider.autoDispose.family<Episode, String>((ref, episodeId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).getEpisode(episodeId);
});

final assetsProvider =
    FutureProvider.autoDispose.family<List<Asset>, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).listAssets(projectId);
});

final shotsProvider =
    FutureProvider.autoDispose.family<List<Shot>, String>((ref, episodeId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).listShots(episodeId);
});

final takesProvider =
    FutureProvider.autoDispose.family<List<VideoTake>, String>((ref, shotId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).listTakes(shotId);
});

final projectJobsProvider =
    FutureProvider.autoDispose.family<List<Job>, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).projectJobs(projectId);
});

final directorStateProvider =
    FutureProvider.autoDispose.family<DirectorState, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(engineProvider).directorState(projectId);
});

final settingsProvider = FutureProvider.autoDispose<AppSettings>(
    (ref) => ref.watch(engineProvider).getSettings());

final healthProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(engineProvider).health());

// ---------- 配置后台 Providers（手动 invalidate，不跟随 jobsGeneration） ----------

final providersProvider = FutureProvider.autoDispose<List<ProviderInfo>>(
    (ref) => ref.watch(engineProvider).listProviders());

final bindingsProvider = FutureProvider.autoDispose<Map<String, String>>(
    (ref) => ref.watch(engineProvider).getBindings());

final promptsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) => ref.watch(engineProvider).listPrompts());
