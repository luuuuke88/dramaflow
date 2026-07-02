import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

Color? _lightAppBarBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? context.df.surface
        : null;

PreferredSizeWidget? _lightAppBarBottom(BuildContext context) {
  if (Theme.of(context).brightness != Brightness.light) return null;
  return PreferredSize(
    preferredSize: const Size.fromHeight(1),
    child: Container(height: 1, color: context.df.stroke),
  );
}

/// 设置页：连接 / 模型服务 / 视频服务。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _lightAppBarBackground(context),
        bottom: _lightAppBarBottom(context),
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
            _appearanceCard(),
            const SizedBox(height: 16),
            _connectionCard(),
            const SizedBox(height: 16),
            _servicesCard(settingsAsync),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ---------- 0. 外观 ----------

  Widget _appearanceCard() {
    final themeMode = ref.watch(themeModeProvider);
    return _SettingsCard(
      title: '外观',
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? context.df.primaryDim
                : context.df.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? context.df.primary
                : context.df.textMid,
          ),
          side: WidgetStateProperty.all(BorderSide(color: context.df.stroke)),
        ),
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined, size: 18),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined, size: 18),
            label: Text('深色'),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined, size: 18),
            label: Text('跟随系统'),
          ),
        ],
        selected: {themeMode},
        onSelectionChanged: (selected) {
          final next = selected.single;
          if (next == themeMode) return;
          runAction(context, ref, () async {
            await ref.read(themeModeProvider.notifier).setThemeMode(next);
          }, successMessage: '外观已更新');
        },
      ),
    );
  }

  // ---------- 1. 存储与引擎 ----------

  Widget _connectionCard() {
    final engine = ref.read(engineProvider);
    return _SettingsCard(
      title: '存储与引擎',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 18, color: context.df.textLo),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  engine.mediaAbsPath(''),
                  style: TextStyle(color: context.df.textMid, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '引擎内嵌运行，数据与媒体全部保存在本机，无需任何后台服务',
            style: TextStyle(color: context.df.textLo, fontSize: 12),
          ),
          const Divider(height: 28),
          Text('引擎状态',
              style: TextStyle(
                  color: context.df.textMid,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _healthStatus(),
        ],
      ),
    );
  }

  Widget _servicesCard(AsyncValue<AppSettings> settingsAsync) {
    return _SettingsCard(
      title: '模型与视频服务',
      child: AsyncView<AppSettings>(
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
            const Divider(height: 24),
            _SettingsGroup(
              title: '火山引擎 · 即梦视频',
              badge: const _VideoServiceBadge(),
              rows: [
                ('模型', s.videoModel),
                ('分辨率', s.videoResolution),
                ('时长', '${s.videoDuration} 秒'),
                ('API Key', s.videoApiKey),
              ],
              onEdit: () => _editVideoGroup(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _healthStatus() {
    final health = ref.watch(healthProvider);
    return health.when(
      skipLoadingOnRefresh: false,
      loading: () => Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: context.df.primary),
          ),
          const SizedBox(width: 10),
          Text('正在检查引擎…',
              style: TextStyle(color: context.df.textLo, fontSize: 13)),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(color: context.df.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.toString(),
                  style: TextStyle(
                      color: context.df.red, fontSize: 13, height: 1.5),
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
                _Dot(color: context.df.green),
                const SizedBox(width: 8),
                Text(
                  '引擎正常 · v${d['version'] ?? '?'}',
                  style: TextStyle(
                      color: context.df.green,
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
                          style: TextStyle(
                              color: context.df.textLo, fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(
                        '${providers[key] ?? '未知'}',
                        style: TextStyle(
                            color: context.df.textMid,
                            fontSize: 12,
                            height: 1.4),
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
                decoration: const InputDecoration(
                    labelText: 'Base URL', hintText: '留空不修改'),
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
                decoration:
                    const InputDecoration(labelText: '模型', hintText: '留空不修改'),
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
      await ref.read(engineProvider).updateSettings(patch);
    }, successMessage: '模型设置已更新');
    if (!mounted) return;
    ref.invalidate(settingsProvider);
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
                    decoration: const InputDecoration(
                        labelText: '模型', hintText: '留空不修改'),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    initialSelection: resolution,
                    label: const Text('分辨率'),
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: false,
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor: context.df.surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: context.df.stroke),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: context.df.stroke),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        borderSide:
                            BorderSide(color: context.df.primary, width: 1.5),
                      ),
                    ),
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
                          TextStyle(color: context.df.textMid, fontSize: 13)),
                  Slider(
                    value: duration,
                    min: 4,
                    max: 15,
                    divisions: 11,
                    label: '${duration.round()}s',
                    activeColor: context.df.primary,
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
      if (modelCtrl.text.trim().isNotEmpty) 'videoModel': modelCtrl.text.trim(),
      'videoResolution': resolution,
      'videoDuration': duration.round(),
      if (keyCtrl.text.trim().isNotEmpty) 'videoApiKey': keyCtrl.text.trim(),
    };

    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateSettings(patch);
    }, successMessage: '视频设置已更新');
    if (!mounted) return;
    ref.invalidate(settingsProvider);
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _VideoServiceBadge extends StatelessWidget {
  const _VideoServiceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.df.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.df.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        '通道已接好 · 待实测',
        style: TextStyle(
          color: context.df.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 组标题 + 只读键值行 + 编辑按钮。
class _SettingsGroup extends StatelessWidget {
  final String title;
  final Widget? badge;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  const _SettingsGroup({
    required this.title,
    this.badge,
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
                style: TextStyle(
                    color: context.df.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 10),
              badge!,
              const SizedBox(width: 8),
            ],
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
                      style: TextStyle(color: context.df.textLo, fontSize: 13)),
                ),
                Expanded(
                  child: Text(
                    value.isEmpty ? '未设置' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: value.isEmpty
                          ? context.df.textLo
                          : context.df.textMid,
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
