import 'package:dio/dio.dart';
import 'models.dart';

/// API 异常：始终带人类可读的中文 message。
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// DramaFlow 后端客户端。所有响应遵循 { ok, data | error } 信封。
class ApiClient {
  String baseUrl;
  String token;
  late final Dio _dio;

  ApiClient({required this.baseUrl, required this.token}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  void configure({required String baseUrl, required String token}) {
    this.baseUrl = baseUrl;
    this.token = token;
  }

  /// 规范化：去掉尾部斜杠和误填的 /api 后缀（路径统一由客户端拼 /api/...）
  String get _root => baseUrl
      .replaceAll(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/api$'), '');

  /// 给媒体相对路径加上主机与 token（Image.network 可直接使用）
  String mediaUrl(String relativeUrl) {
    return '$_root$relativeUrl?token=$token';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.request(
        '$_root$path',
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (_) => true,
        ),
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['ok'] == true) return data['data'];
        throw ApiException(
          data['error'] as String? ?? '未知错误 (HTTP ${res.statusCode})',
          statusCode: res.statusCode,
        );
      }
      throw ApiException('响应格式异常 (HTTP ${res.statusCode})',
          statusCode: res.statusCode);
    } on DioException catch (e) {
      throw ApiException(switch (e.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout =>
          '无法连接到后端服务（$baseUrl）\n请确认服务已启动',
        DioExceptionType.receiveTimeout => '后端响应超时',
        _ => '网络错误：${e.message}',
      });
    }
  }

  // ---- health / settings ----

  Future<Map<String, dynamic>> health() async =>
      (await _request('GET', '/api/health')) as Map<String, dynamic>;

  Future<AppSettings> getSettings() async => AppSettings.fromJson(
      (await _request('GET', '/api/settings')) as Map<String, dynamic>);

  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async =>
      AppSettings.fromJson(
          (await _request('PUT', '/api/settings', body: patch))
              as Map<String, dynamic>);

  // ---- projects ----

  Future<List<Project>> listProjects() async =>
      ((await _request('GET', '/api/projects')) as List)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<Project> createProject(String name, {String artStyle = ''}) async =>
      Project.fromJson((await _request('POST', '/api/projects',
          body: {'name': name, 'artStyle': artStyle})) as Map<String, dynamic>);

  Future<Project> getProject(String id) async => Project.fromJson(
      (await _request('GET', '/api/projects/$id')) as Map<String, dynamic>);

  Future<Project> updateProject(String id,
          {String? name, String? artStyle}) async =>
      Project.fromJson((await _request('PATCH', '/api/projects/$id', body: {
        if (name != null) 'name': name,
        if (artStyle != null) 'artStyle': artStyle,
      })) as Map<String, dynamic>);

  Future<void> deleteProject(String id) async =>
      _request('DELETE', '/api/projects/$id');

  // ---- novel ----

  Future<Novel?> getNovel(String projectId) async {
    final data = await _request('GET', '/api/projects/$projectId/novel');
    return data == null ? null : Novel.fromJson(data as Map<String, dynamic>);
  }

  Future<Novel> saveNovel(String projectId,
          {required String title, required String content}) async =>
      Novel.fromJson((await _request('PUT', '/api/projects/$projectId/novel',
          body: {'title': title, 'content': content})) as Map<String, dynamic>);

  // ---- pipeline actions ----

  Future<String> generateScript(String projectId, {int? episodeCount}) async {
    final data = await _request(
        'POST', '/api/projects/$projectId/generate-script',
        body: {if (episodeCount != null) 'episodeCount': episodeCount});
    return (data as Map<String, dynamic>)['jobId'] as String;
  }

  Future<String> extractAssets(String projectId) async {
    final data =
        await _request('POST', '/api/projects/$projectId/extract-assets');
    return (data as Map<String, dynamic>)['jobId'] as String;
  }

  Future<String> generateStoryboard(String episodeId) async {
    final data =
        await _request('POST', '/api/episodes/$episodeId/generate-storyboard');
    return (data as Map<String, dynamic>)['jobId'] as String;
  }

  // ---- episodes ----

  Future<List<EpisodeSummary>> listEpisodes(String projectId) async =>
      ((await _request('GET', '/api/projects/$projectId/episodes')) as List)
          .map((e) => EpisodeSummary.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<Episode> getEpisode(String id) async => Episode.fromJson(
      (await _request('GET', '/api/episodes/$id')) as Map<String, dynamic>);

  Future<Episode> updateEpisode(String id,
          {String? title, String? synopsis, List<Scene>? scenes}) async =>
      Episode.fromJson((await _request('PUT', '/api/episodes/$id', body: {
        if (title != null) 'title': title,
        if (synopsis != null) 'synopsis': synopsis,
        if (scenes != null) 'scenes': scenes.map((s) => s.toJson()).toList(),
      })) as Map<String, dynamic>);

  // ---- assets ----

  Future<List<Asset>> listAssets(String projectId) async =>
      ((await _request('GET', '/api/projects/$projectId/assets')) as List)
          .map((e) => Asset.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<Asset> updateAsset(String id,
          {String? name, String? description, String? imagePrompt}) async =>
      Asset.fromJson((await _request('PATCH', '/api/assets/$id', body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (imagePrompt != null) 'imagePrompt': imagePrompt,
      })) as Map<String, dynamic>);

  Future<String?> generateAssetImage(String assetId) async {
    final data = await _request('POST', '/api/assets/$assetId/generate-image');
    return (data as Map<String, dynamic>)['jobId'] as String?;
  }

  Future<List<String>> generateAllAssetImages(String projectId) async {
    final data = await _request(
        'POST', '/api/projects/$projectId/generate-all-asset-images');
    return ((data as Map<String, dynamic>)['jobIds'] as List)
        .map((e) => e.toString())
        .toList();
  }

  // ---- shots ----

  Future<List<Shot>> listShots(String episodeId) async =>
      ((await _request('GET', '/api/episodes/$episodeId/shots')) as List)
          .map((e) => Shot.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<Shot> updateShot(String id, Map<String, String> patch) async =>
      Shot.fromJson((await _request('PATCH', '/api/shots/$id', body: patch))
          as Map<String, dynamic>);

  Future<String?> generateShotImage(String shotId) async {
    final data = await _request('POST', '/api/shots/$shotId/generate-image');
    return (data as Map<String, dynamic>)['jobId'] as String?;
  }

  Future<List<String>> generateAllShotImages(String episodeId) async {
    final data = await _request(
        'POST', '/api/episodes/$episodeId/generate-all-shot-images');
    return ((data as Map<String, dynamic>)['jobIds'] as List)
        .map((e) => e.toString())
        .toList();
  }

  Future<String> generateShotVideo(String shotId) async {
    final data = await _request('POST', '/api/shots/$shotId/generate-video');
    return (data as Map<String, dynamic>)['jobId'] as String;
  }

  // ---- jobs ----

  Future<List<Job>> activeJobs() async =>
      ((await _request('GET', '/api/jobs/active')) as List)
          .map((e) => Job.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<Job>> projectJobs(String projectId, {int limit = 50}) async =>
      ((await _request('GET', '/api/projects/$projectId/jobs',
              query: {'limit': limit})) as List)
          .map((e) => Job.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<String> retryJob(String jobId) async {
    final data = await _request('POST', '/api/jobs/$jobId/retry');
    return (data as Map<String, dynamic>)['jobId'] as String;
  }

  Future<void> cancelJob(String jobId) async =>
      _request('POST', '/api/jobs/$jobId/cancel');
}
