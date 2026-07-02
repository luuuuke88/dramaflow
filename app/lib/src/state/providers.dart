import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../api/models.dart';

/// 客户端连接配置（后端地址 + token）。桌面/移动端默认连本机。
class ConnectionConfig {
  final String baseUrl;
  final String token;
  const ConnectionConfig({required this.baseUrl, required this.token});
}

class ConnectionNotifier extends Notifier<ConnectionConfig> {
  @override
  ConnectionConfig build() =>
      const ConnectionConfig(baseUrl: 'http://127.0.0.1:8620', token: 'local-dev');

  void update({String? baseUrl, String? token}) {
    state = ConnectionConfig(
      baseUrl: baseUrl ?? state.baseUrl,
      token: token ?? state.token,
    );
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionConfig>(ConnectionNotifier.new);

final apiProvider = Provider<ApiClient>((ref) {
  final conn = ref.watch(connectionProvider);
  return ApiClient(baseUrl: conn.baseUrl, token: conn.token);
});

/// 活跃任务轮询器：有活跃任务时 2s 一拍，空闲时 6s 一拍。
/// 任务集合发生变化（有任务完成/新增）时自增 [jobsGeneration]，
/// 数据 Provider 监听它来自动刷新列表。
class ActiveJobsNotifier extends Notifier<List<Job>> {
  Timer? _timer;
  bool _fetching = false;

  @override
  List<Job> build() {
    ref.onDispose(() => _timer?.cancel());
    _schedule(const Duration(milliseconds: 300));
    return const [];
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _tick);
  }

  Future<void> _tick() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final jobs = await ref.read(apiProvider).activeJobs();
      final oldIds = state.map((j) => '${j.id}:${j.state}').join(',');
      final newIds = jobs.map((j) => '${j.id}:${j.state}').join(',');
      if (oldIds != newIds) {
        state = jobs;
        ref.read(jobsGenerationProvider.notifier).bump();
      }
    } catch (_) {
      // 后端暂时不可达：保持现状，下一拍重试
    } finally {
      _fetching = false;
      _schedule(Duration(seconds: state.isEmpty ? 6 : 2));
    }
  }

  /// 发起生成动作后立即触发一次轮询（让"排队中"立刻可见）
  void poke() => _schedule(const Duration(milliseconds: 200));
}

final activeJobsProvider =
    NotifierProvider<ActiveJobsNotifier, List<Job>>(ActiveJobsNotifier.new);

/// 数据刷新信号：任务集合每次变化 +1。
/// 各数据 Provider watch 它 → 任务完成时列表自动重新拉取。
class JobsGenerationNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final jobsGenerationProvider =
    NotifierProvider<JobsGenerationNotifier, int>(JobsGenerationNotifier.new);

// ---------- 数据 Providers（全部跟随 jobsGeneration 自动刷新）----------

final projectsProvider = FutureProvider.autoDispose<List<Project>>((ref) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).listProjects();
});

final projectProvider =
    FutureProvider.autoDispose.family<Project, String>((ref, id) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).getProject(id);
});

final novelProvider =
    FutureProvider.autoDispose.family<Novel?, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).getNovel(projectId);
});

final episodesProvider = FutureProvider.autoDispose
    .family<List<EpisodeSummary>, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).listEpisodes(projectId);
});

final episodeProvider =
    FutureProvider.autoDispose.family<Episode, String>((ref, episodeId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).getEpisode(episodeId);
});

final assetsProvider =
    FutureProvider.autoDispose.family<List<Asset>, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).listAssets(projectId);
});

final shotsProvider =
    FutureProvider.autoDispose.family<List<Shot>, String>((ref, episodeId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).listShots(episodeId);
});

final projectJobsProvider =
    FutureProvider.autoDispose.family<List<Job>, String>((ref, projectId) {
  ref.watch(jobsGenerationProvider);
  return ref.watch(apiProvider).projectJobs(projectId);
});

final settingsProvider = FutureProvider.autoDispose<AppSettings>(
    (ref) => ref.watch(apiProvider).getSettings());

final healthProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.watch(apiProvider).health());
