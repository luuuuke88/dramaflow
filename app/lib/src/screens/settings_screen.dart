import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 设置页：连接 / 模型服务 / 视频服务。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _tokenCtrl;

  @override
  void initState() {
    super.initState();
    final conn = ref.read(connectionProvider);
    _baseUrlCtrl = TextEditingController(text: conn.baseUrl);
    _tokenCtrl = TextEditingController(text: conn.token);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(settingsProvider);
              ref.invalidate(healthProvider);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageContainer(
        maxWidth: 760,
        child: ListView(
          children: [
            const SizedBox(height: 12),
            _connectionCard(),
            const SizedBox(height: 16),
            _modelServicesCard(settingsAsync),
            const SizedBox(height: 16),
            _videoServiceCard(settingsAsync),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ---------- 1. 连接 ----------

  Widget _connectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('连接', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: '后端地址',
                hintText: 'http://127.0.0.1:8620',
                prefixIcon: Icon(Icons.dns_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: '访问令牌 Token',
                prefixIcon: Icon(Icons.key_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '默认连接本机 127.0.0.1:8620',
              style: TextStyle(color: DF.textLo, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存'),
                onPressed: _saveConnection,
              ),
            ),
            const Divider(height: 28),
            const Text('健康状态',
                style: TextStyle(
                    color: DF.textMid,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _healthStatus(),
          ],
        ),
      ),
    );
  }

  Future<void> _saveConnection() => runAction(context, ref, () async {
        ref.read(connectionProvider.notifier).update(
              baseUrl: _baseUrlCtrl.text.trim(),
              token: _tokenCtrl.text.trim(),
            );
        ref.invalidate(healthProvider);
      }, successMessage: '连接设置已保存');

  Widget _healthStatus() {
    final health = ref.watch(healthProvider);
    return health.when(
      skipLoadingOnRefresh: false,
      loading: () => const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: DF.amber),
          ),
          SizedBox(width: 10),
          Text('正在检查后端服务…',
              style: TextStyle(color: DF.textLo, fontSize: 13)),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Dot(color: DF.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.toString(),
                  style: const TextStyle(
                      color: DF.red, fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
            onPressed: () => ref.invalidate(healthProvider),
          ),
        ],
      ),
      data: (d) {
        final providers =
            (d['providers'] as Map?)?.cast<String, dynamic>() ?? const {};
        const labels = [
          ('text', '文本'),
          ('image', '图片'),
          ('video', '视频'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Dot(color: DF.green),
                const SizedBox(width: 8),
                Text(
                  '服务正常 · v${d['version'] ?? '?'}',
                  style: const TextStyle(
                      color: DF.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (key, label) in labels)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(label,
                          style: const TextStyle(
                              color: DF.textLo, fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(
                        '${providers[key] ?? '未知'}',
                        style: const TextStyle(
                            color: DF.textMid, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------- 2. 模型服务 ----------

  Widget _modelServicesCard(AsyncValue<AppSettings> settingsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模型服务', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            AsyncView<AppSettings>(
              value: settingsAsync,
              onRetry: () => ref.invalidate(settingsProvider),
              builder: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsGroup(
                    title: '文本模型',
                    rows: [
                      ('Base URL', s.textBaseUrl),
                      ('模型', s.textModel),
                    ],
                    onEdit: () => _editModelGroup(
                      title: '编辑文本模型',
                      baseUrl: s.textBaseUrl,
                      model: s.textModel,
                      baseUrlKey: 'textBaseUrl',
                      apiKeyKey: 'textApiKey',
                      modelKey: 'textModel',
                    ),
                  ),
                  const Divider(height: 24),
                  _SettingsGroup(
                    title: '图片模型',
                    rows: [
                      ('Base URL', s.imageBaseUrl),
                      ('模型', s.imageModel),
                    ],
                    onEdit: () => _editModelGroup(
                      title: '编辑图片模型',
                      baseUrl: s.imageBaseUrl,
                      model: s.imageModel,
                      baseUrlKey: 'imageBaseUrl',
                      apiKeyKey: 'imageApiKey',
                      modelKey: 'imageModel',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editModelGroup({
    required String title,
    required String baseUrl,
    required String model,
    required String baseUrlKey,
    required String apiKeyKey,
    required String modelKey,
  }) async {
    final baseCtrl = TextEditingController(text: baseUrl);
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController(text: model);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseCtrl,
                decoration: const InputDecoration(labelText: 'Base URL'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '留空不修改',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: '模型'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final patch = <String, dynamic>{
      if (baseCtrl.text.trim().isNotEmpty) baseUrlKey: baseCtrl.text.trim(),
      if (keyCtrl.text.trim().isNotEmpty) apiKeyKey: keyCtrl.text.trim(),
      if (modelCtrl.text.trim().isNotEmpty) modelKey: modelCtrl.text.trim(),
    };
    if (patch.isEmpty) return;

    await runAction(context, ref, () async {
      await ref.read(apiProvider).updateSettings(patch);
      ref.invalidate(settingsProvider);
    }, successMessage: '模型设置已更新');
  }

  // ---------- 3. 视频服务 ----------

  Widget _videoServiceCard(AsyncValue<AppSettings> settingsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('视频服务',
                    style: Theme.of(context).textTheme.titleMedium),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DF.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: DF.amber.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    '通道已接好 · 待实测',
                    style: TextStyle(
                        color: DF.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AsyncView<AppSettings>(
              value: settingsAsync,
              onRetry: () => ref.invalidate(settingsProvider),
              builder: (s) => _SettingsGroup(
                title: '火山引擎 · 即梦视频',
                rows: [
                  ('模型', s.videoModel),
                  ('分辨率', s.videoResolution),
                  ('时长', '${s.videoDuration} 秒'),
                  ('API Key', s.videoApiKey),
                ],
                onEdit: () => _editVideoGroup(s),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editVideoGroup(AppSettings s) async {
    final modelCtrl = TextEditingController(text: s.videoModel);
    final keyCtrl = TextEditingController();
    const resolutions = ['480p', '720p'];
    var resolution =
        resolutions.contains(s.videoResolution) ? s.videoResolution : '720p';
    var duration = s.videoDuration.clamp(4, 15).toDouble();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑视频服务'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(labelText: '模型'),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    initialSelection: resolution,
                    label: const Text('分辨率'),
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: false,
                    dropdownMenuEntries: [
                      for (final r in resolutions)
                        DropdownMenuEntry(value: r, label: r),
                    ],
                    onSelected: (v) {
                      if (v != null) resolution = v;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('时长：${duration.round()} 秒',
                      style:
                          const TextStyle(color: DF.textMid, fontSize: 13)),
                  Slider(
                    value: duration,
                    min: 4,
                    max: 15,
                    divisions: 11,
                    label: '${duration.round()}s',
                    activeColor: DF.amber,
                    onChanged: (v) => setDialogState(() => duration = v),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: keyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: '留空不修改',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final patch = <String, dynamic>{
      if (modelCtrl.text.trim().isNotEmpty)
        'videoModel': modelCtrl.text.trim(),
      'videoResolution': resolution,
      'videoDuration': duration.round(),
      if (keyCtrl.text.trim().isNotEmpty) 'videoApiKey': keyCtrl.text.trim(),
    };

    await runAction(context, ref, () async {
      await ref.read(apiProvider).updateSettings(patch);
      ref.invalidate(settingsProvider);
    }, successMessage: '视频设置已更新');
  }
}

/// 组标题 + 只读键值行 + 编辑按钮。
class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  const _SettingsGroup({
    required this.title,
    required this.rows,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    color: DF.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('编辑'),
              onPressed: onEdit,
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(label,
                      style:
                          const TextStyle(color: DF.textLo, fontSize: 13)),
                ),
                Expanded(
                  child: Text(
                    value.isEmpty ? '未设置' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: value.isEmpty ? DF.textLo : DF.textMid,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
