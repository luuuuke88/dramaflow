import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../engine/util.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
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

enum _SettingsSection { appearance, providers, bindings, prompts, storage }

const _sections = [
  _SectionMeta(_SettingsSection.appearance, '外观', Icons.palette_outlined),
  _SectionMeta(_SettingsSection.providers, '供应商', Icons.cloud_queue_rounded),
  _SectionMeta(_SettingsSection.bindings, '模型绑定', Icons.hub_outlined),
  _SectionMeta(_SettingsSection.prompts, '提示词', Icons.article_outlined),
  _SectionMeta(_SettingsSection.storage, '存储与引擎', Icons.storage_outlined),
];

const _stages = [
  _StageMeta('script_gen', '剧本生成', '把小说改编为短剧剧本', 'text'),
  _StageMeta('asset_extract', '素材提取', '从剧本提取角色、场景和道具', 'text'),
  _StageMeta('storyboard_gen', '分镜生成', '按集拆解镜头与镜头提示词', 'text'),
  _StageMeta('asset_image', '素材图生成', '生成角色、场景、道具资产图', 'image'),
  _StageMeta('shot_image', '镜头图生成', '生成每个镜头的静帧画面', 'image'),
  _StageMeta('shot_video', '镜头视频生成', '从镜头图生成短视频片段', 'video'),
  _StageMeta('tts', '配音生成', '为镜头台词生成语音', 'tts'),
];

const _promptMetas = [
  _PromptMeta('script_gen_system', '剧本生成', '小说改编为短剧剧本的系统提示词'),
  _PromptMeta('asset_extract_system', '素材提取', '角色、场景、道具提取规则'),
  _PromptMeta('storyboard_gen_system', '分镜生成', '分镜表拆解与镜头提示词规则'),
  _PromptMeta('image_size_directive', '图片尺寸指令', '注入图片生成请求的尺寸约束'),
];

const _modelKinds = [
  _KindMeta('text', '文本'),
  _KindMeta('image', '图片'),
  _KindMeta('video', '视频'),
  _KindMeta('tts', '配音'),
];

class _SectionMeta {
  final _SettingsSection section;
  final String label;
  final IconData icon;

  const _SectionMeta(this.section, this.label, this.icon);
}

class _StageMeta {
  final String key;
  final String title;
  final String description;
  final String kind;

  const _StageMeta(this.key, this.title, this.description, this.kind);
}

class _PromptMeta {
  final String key;
  final String title;
  final String description;

  const _PromptMeta(this.key, this.title, this.description);
}

class _KindMeta {
  final String value;
  final String label;

  const _KindMeta(this.value, this.label);
}

/// 设置页：M2 配置后台（供应商 / 模型绑定 / 提示词）+ 外观与本机存储。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.appearance;
  int _modelRevision = 0;

  void _selectSection(_SettingsSection section) {
    if (section == _section) return;
    setState(() => _section = section);
  }

  void _invalidateConfig() {
    ref.invalidate(providersProvider);
    ref.invalidate(bindingsProvider);
    ref.invalidate(promptsProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(healthProvider);
    setState(() => _modelRevision++);
  }

  void _invalidateProvidersAndBindings() {
    ref.invalidate(providersProvider);
    ref.invalidate(bindingsProvider);
    ref.invalidate(healthProvider);
    setState(() => _modelRevision++);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _lightAppBarBackground(context),
        bottom: _lightAppBarBottom(context),
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _invalidateConfig,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageContainer(
        maxWidth: 1240,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _SideNav(
                      selected: _section,
                      onSelected: _selectSection,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: _sectionBody()),
                ],
              )
            : Column(
                children: [
                  const SizedBox(height: 12),
                  _TopSectionTabs(
                    selected: _section,
                    onSelected: _selectSection,
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _sectionBody()),
                ],
              ),
      ),
    );
  }

  Widget _sectionBody() {
    return ListView(
      children: [
        const SizedBox(height: 16),
        switch (_section) {
          _SettingsSection.appearance => _appearanceCard(),
          _SettingsSection.providers => _providersPanel(),
          _SettingsSection.bindings => _bindingsPanel(),
          _SettingsSection.prompts => _promptsPanel(),
          _SettingsSection.storage => _storageCard(),
        },
        const SizedBox(height: 40),
      ],
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

  // ---------- 1. 供应商 ----------

  Widget _providersPanel() {
    final providersAsync = ref.watch(providersProvider);
    return _SettingsCard(
      title: '供应商',
      trailing: FilledButton.icon(
        onPressed: _openCreateProviderDialog,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('添加供应商'),
      ),
      child: AsyncView<List<ProviderInfo>>(
        value: providersAsync,
        onRetry: () => ref.invalidate(providersProvider),
        builder: (providers) {
          if (providers.isEmpty) {
            return EmptyHint(
              icon: Icons.cloud_off_outlined,
              title: '还没有供应商',
              subtitle: '添加 OpenAI 兼容或火山引擎供应商后，再配置模型和环节绑定',
              action: FilledButton.icon(
                onPressed: _openCreateProviderDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加供应商'),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    for (final provider in providers)
                      _ProviderCard(
                        key: ValueKey('${provider.id}:$_modelRevision'),
                        provider: provider,
                        loadModels: () => _listProviderModels(provider.id),
                        onEdit: () => _openEditProviderDialog(provider),
                        onManageModels: () => _openModelsEditor(provider),
                        onTest: () => _testProvider(provider),
                        onDelete: () => _deleteProvider(provider),
                        onEnabledChanged: (enabled) =>
                            _setProviderEnabled(provider, enabled),
                      ),
                  ],
                );
              }

              return _ProviderTable(
                providers: providers,
                revision: _modelRevision,
                loadModels: _listProviderModels,
                onEdit: _openEditProviderDialog,
                onManageModels: _openModelsEditor,
                onTest: _testProvider,
                onDelete: _deleteProvider,
                onEnabledChanged: _setProviderEnabled,
              );
            },
          );
        },
      ),
    );
  }

  Future<List<ProviderModelInfo>> _listProviderModels(String providerId) {
    return ref.read(engineProvider).listProviderModels(providerId);
  }

  Future<void> _openCreateProviderDialog() async {
    final result = await showDialog<_ProviderFormResult>(
      context: context,
      builder: (_) => const _ProviderFormDialog(),
    );
    if (result == null || !mounted) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).createProvider(
            name: result.name,
            protocol: result.protocol,
            baseUrl: result.baseUrl,
            apiKey: result.apiKey,
          );
    }, successMessage: '供应商已添加');
    if (!mounted) return;
    _invalidateProvidersAndBindings();
  }

  Future<void> _openEditProviderDialog(ProviderInfo provider) async {
    final result = await showDialog<_ProviderFormResult>(
      context: context,
      builder: (_) => _ProviderFormDialog(provider: provider),
    );
    if (result == null || !mounted) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateProvider(
            provider.id,
            name: result.name.isEmpty ? null : result.name,
            baseUrl: result.baseUrl.isEmpty ? null : result.baseUrl,
            apiKey: result.apiKey.isEmpty ? null : result.apiKey,
          );
    }, successMessage: '供应商已更新');
    if (!mounted) return;
    _invalidateProvidersAndBindings();
  }

  Future<void> _setProviderEnabled(ProviderInfo provider, bool enabled) async {
    await runAction(context, ref, () async {
      final data = await ref.read(engineProvider).exportConfig();
      final providers = data['providers'];
      if (providers is! List) {
        throw EngineException('配置数据缺少供应商列表');
      }

      var changed = false;
      for (var i = 0; i < providers.length; i++) {
        final raw = providers[i];
        if (raw is! Map) continue;
        if ((raw['id'] ?? '').toString() != provider.id) continue;
        final next = Map<String, dynamic>.from(raw);
        next['enabled'] = enabled;
        providers[i] = next;
        changed = true;
        break;
      }
      if (!changed) throw EngineException('供应商不存在');
      await ref.read(engineProvider).importConfig(data);
    }, successMessage: enabled ? '供应商已启用' : '供应商已停用');
    if (!mounted) return;
    _invalidateProvidersAndBindings();
  }

  Future<void> _openModelsEditor(ProviderInfo provider) async {
    final models = await _loadModelsForEditor(provider);
    if (models == null || !mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ProviderModelsEditor(
          provider: provider,
          models: models,
        ),
        fullscreenDialog: true,
      ),
    );
    if (saved == true && mounted) _invalidateProvidersAndBindings();
  }

  Future<List<ProviderModelInfo>?> _loadModelsForEditor(
      ProviderInfo provider) async {
    List<ProviderModelInfo>? models;
    await runAction(context, ref, () async {
      models = await ref.read(engineProvider).listProviderModels(provider.id);
    });
    return models;
  }

  Future<void> _testProvider(ProviderInfo provider) async {
    List<ProviderModelInfo>? models;
    await runAction(context, ref, () async {
      models = await ref.read(engineProvider).listProviderModels(provider.id);
    });
    if (!mounted || models == null) return;

    final textModels = models!
        .where((model) => model.kind == 'text' && model.enabled)
        .toList();
    if (textModels.isEmpty) {
      await runAction(context, ref, () async {
        throw EngineException('请先启用至少一个文本模型');
      });
      return;
    }

    ProviderModelInfo? selected = textModels.length == 1
        ? textModels.first
        : await _chooseTextModel(provider, textModels);
    if (!mounted || selected == null) return;

    var elapsedMs = 0;
    await runAction(context, ref, () async {
      elapsedMs = await ref
          .read(engineProvider)
          .testProvider(provider.id, selected.modelId);
    }, successMessage: '连通成功：$elapsedMs ms');
  }

  Future<ProviderModelInfo?> _chooseTextModel(
      ProviderInfo provider, List<ProviderModelInfo> models) {
    var selected = models.first;
    return showDialog<ProviderModelInfo>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('测试连通 · ${provider.name}'),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<ProviderModelInfo>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: '文本模型'),
              items: [
                for (final model in models)
                  DropdownMenuItem(
                    value: model,
                    child: Text(_modelLabel(model)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setDialogState(() => selected = value);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text('测试'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProvider(ProviderInfo provider) async {
    final confirmed = await _confirm(
      title: '删除供应商',
      message: '确定删除“${provider.name}”吗？如果供应商已被环节绑定，引擎会拒绝删除。',
      confirmText: '删除',
      destructive: true,
    );
    if (!mounted || !confirmed) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).deleteProvider(provider.id);
    }, successMessage: '供应商已删除');
    if (!mounted) return;
    _invalidateProvidersAndBindings();
  }

  // ---------- 2. 模型绑定 ----------

  Widget _bindingsPanel() {
    final providersAsync = ref.watch(providersProvider);
    final bindingsAsync = ref.watch(bindingsProvider);
    return _SettingsCard(
      title: '模型绑定',
      child: AsyncView<List<ProviderInfo>>(
        value: providersAsync,
        onRetry: () => ref.invalidate(providersProvider),
        builder: (providers) => AsyncView<Map<String, String>>(
          value: bindingsAsync,
          onRetry: () => ref.invalidate(bindingsProvider),
          builder: (bindings) => FutureBuilder<List<_ModelOption>>(
            future: _loadModelOptions(providers),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return ErrorCard(
                  message: snapshot.error.toString(),
                  onRetry: () => setState(() => _modelRevision++),
                );
              }
              final options = snapshot.data ?? const <_ModelOption>[];
              return Column(
                children: [
                  for (final stage in _stages)
                    _BindingRow(
                      stage: stage,
                      binding: bindings[stage.key],
                      options: options
                          .where((option) => option.kind == stage.kind)
                          .toList(),
                      onChanged: (value) => _setBinding(stage, value),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<_ModelOption>> _loadModelOptions(
      List<ProviderInfo> providers) async {
    final options = <_ModelOption>[];
    for (final provider in providers.where((p) => p.enabled)) {
      final models = await ref.read(engineProvider).listProviderModels(
            provider.id,
          );
      for (final model in models.where((m) => m.enabled)) {
        options.add(_ModelOption(provider: provider, model: model));
      }
    }
    options.sort((a, b) {
      final kind = a.kind.compareTo(b.kind);
      if (kind != 0) return kind;
      final provider = a.provider.name.compareTo(b.provider.name);
      if (provider != 0) return provider;
      return a.label.compareTo(b.label);
    });
    return options;
  }

  Future<void> _setBinding(_StageMeta stage, String value) async {
    final sep = value.indexOf(':');
    if (sep <= 0 || sep == value.length - 1) return;
    final providerId = value.substring(0, sep);
    final modelId = value.substring(sep + 1);

    await runAction(context, ref, () async {
      await ref.read(engineProvider).setBinding(stage.key, providerId, modelId);
    }, successMessage: '${stage.title}绑定已更新');
    if (!mounted) return;
    ref.invalidate(bindingsProvider);
    ref.invalidate(healthProvider);
  }

  // ---------- 3. 提示词 ----------

  Widget _promptsPanel() {
    final promptsAsync = ref.watch(promptsProvider);
    return _SettingsCard(
      title: '提示词',
      child: AsyncView<List<Map<String, dynamic>>>(
        value: promptsAsync,
        onRetry: () => ref.invalidate(promptsProvider),
        builder: (prompts) {
          final byKey = {
            for (final prompt in prompts)
              (prompt['key'] ?? '').toString(): prompt
          };
          return Column(
            children: [
              for (final meta in _promptMetas)
                _PromptRow(
                  meta: meta,
                  prompt: byKey[meta.key],
                  onOpen: () => _openPromptEditor(meta, byKey[meta.key]),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPromptEditor(
      _PromptMeta meta, Map<String, dynamic>? prompt) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PromptEditorPage(
          meta: meta,
          initialContent: (prompt?['content'] ?? '').toString(),
        ),
        fullscreenDialog: true,
      ),
    );
    if (saved == true && mounted) {
      ref.invalidate(promptsProvider);
    }
  }

  // ---------- 4. 存储与引擎 ----------

  Widget _storageCard() {
    final engine = ref.read(engineProvider);
    return _SettingsCard(
      title: '存储与引擎',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _exportConfig,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导出配置'),
              ),
              OutlinedButton.icon(
                onPressed: _importConfig,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导入配置'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '配置 JSON 包含明文密钥，请妥善保管。',
            style: TextStyle(color: context.df.textLo, fontSize: 12),
          ),
          const Divider(height: 28),
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

  Future<void> _exportConfig() async {
    final fileName =
        'dramaflow-config-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: fileName,
      );
    } catch (e) {
      if (!mounted) return;
      await runAction(context, ref, () async {
        throw EngineException('无法打开保存面板：$e');
      });
      return;
    }
    if (!mounted || location == null) return;

    await runAction(context, ref, () async {
      try {
        final data = await ref.read(engineProvider).exportConfig();
        const encoder = JsonEncoder.withIndent('  ');
        final file = XFile.fromData(
          Uint8List.fromList(utf8.encode(encoder.convert(data))),
          mimeType: 'application/json',
          name: fileName,
        );
        await file.saveTo(location!.path);
      } on EngineException {
        rethrow;
      } catch (e) {
        throw EngineException('导出配置失败：$e');
      }
    }, successMessage: '配置已导出');
  }

  Future<void> _importConfig() async {
    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JSON',
            extensions: ['json'],
            mimeTypes: ['application/json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      await runAction(context, ref, () async {
        throw EngineException('无法打开文件选择器：$e');
      });
      return;
    }
    if (!mounted || file == null) return;

    final confirmed = await _confirm(
      title: '导入配置',
      message: '导入会覆盖同名供应商、模型、绑定和提示词。确定继续吗？',
      confirmText: '导入',
    );
    if (!mounted || !confirmed) return;

    await runAction(context, ref, () async {
      try {
        final raw = await file!.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw EngineException('配置文件格式无效');
        }
        await ref
            .read(engineProvider)
            .importConfig(Map<String, dynamic>.from(decoded));
      } on FormatException {
        throw EngineException('配置文件不是有效 JSON');
      } on EngineException {
        rethrow;
      } catch (e) {
        throw EngineException('导入配置失败：$e');
      }
    }, successMessage: '配置已导入');
    if (!mounted) return;
    _invalidateConfig();
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

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: context.df.red)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

class _TopSectionTabs extends StatelessWidget {
  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;

  const _TopSectionTabs({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_SettingsSection>(
          showSelectedIcon: false,
          selected: {selected},
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
          segments: [
            for (final item in _sections)
              ButtonSegment(
                value: item.section,
                icon: Icon(item.icon, size: 18),
                label: Text(item.label),
              ),
          ],
          onSelectionChanged: (selected) => onSelected(selected.single),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;

  const _SideNav({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _sections)
            _SideNavItem(
              item: item,
              selected: selected == item.section,
              onTap: () => onSelected(item.section),
            ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final _SectionMeta item;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.df.primary : context.df.textMid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? context.df.primaryDim : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SettingsCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
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

class _ProviderTable extends StatelessWidget {
  final List<ProviderInfo> providers;
  final int revision;
  final Future<List<ProviderModelInfo>> Function(String providerId) loadModels;
  final ValueChanged<ProviderInfo> onEdit;
  final ValueChanged<ProviderInfo> onManageModels;
  final ValueChanged<ProviderInfo> onTest;
  final ValueChanged<ProviderInfo> onDelete;
  final void Function(ProviderInfo provider, bool enabled) onEnabledChanged;

  const _ProviderTable({
    required this.providers,
    required this.revision,
    required this.loadModels,
    required this.onEdit,
    required this.onManageModels,
    required this.onTest,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        children: [
          _ProviderTableHeader(),
          for (final provider in providers)
            _ProviderTableRow(
              key: ValueKey('${provider.id}:$revision'),
              provider: provider,
              loadModels: () => loadModels(provider.id),
              onEdit: () => onEdit(provider),
              onManageModels: () => onManageModels(provider),
              onTest: () => onTest(provider),
              onDelete: () => onDelete(provider),
              onEnabledChanged: (enabled) =>
                  onEnabledChanged(provider, enabled),
            ),
        ],
      ),
    );
  }
}

class _ProviderTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.df.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: const Row(
        children: [
          _HeaderFlexCell(flex: 14, label: '名称'),
          _HeaderCell(width: 118, label: '协议'),
          _HeaderFlexCell(flex: 24, label: 'Base URL'),
          _HeaderCell(width: 92, label: '启用'),
          _HeaderCell(width: 72, label: '模型'),
          _HeaderCell(width: 184, label: '操作'),
        ],
      ),
    );
  }
}

class _ProviderTableRow extends StatelessWidget {
  final ProviderInfo provider;
  final Future<List<ProviderModelInfo>> Function() loadModels;
  final VoidCallback onEdit;
  final VoidCallback onManageModels;
  final VoidCallback onTest;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  const _ProviderTableRow({
    super.key,
    required this.provider,
    required this.loadModels,
    required this.onEdit,
    required this.onManageModels,
    required this.onTest,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: Row(
        children: [
          _TextFlexCell(
            flex: 14,
            text: provider.name,
            style: TextStyle(
              color: context.df.textHi,
              fontWeight: FontWeight.w700,
            ),
          ),
          _FixedCell(
            width: 118,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ProtocolBadge(protocol: provider.protocol),
            ),
          ),
          _TextFlexCell(
            flex: 24,
            text: provider.baseUrl,
            emptyText: '未设置',
            tooltip: provider.baseUrl,
          ),
          _FixedCell(
            width: 92,
            child: Switch(
              value: provider.enabled,
              onChanged: onEnabledChanged,
            ),
          ),
          _FixedCell(
            width: 72,
            child: FutureBuilder<List<ProviderModelInfo>>(
              future: loadModels(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length;
                return Text(
                  count == null ? '…' : '$count',
                  style: TextStyle(
                    color: context.df.textMid,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          _FixedCell(
            width: 184,
            child: _ProviderActions(
              onEdit: onEdit,
              onManageModels: onManageModels,
              onTest: onTest,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final ProviderInfo provider;
  final Future<List<ProviderModelInfo>> Function() loadModels;
  final VoidCallback onEdit;
  final VoidCallback onManageModels;
  final VoidCallback onTest;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  const _ProviderCard({
    super.key,
    required this.provider,
    required this.loadModels,
    required this.onEdit,
    required this.onManageModels,
    required this.onTest,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.name,
                  style: TextStyle(
                    color: context.df.textHi,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(value: provider.enabled, onChanged: onEnabledChanged),
            ],
          ),
          const SizedBox(height: 8),
          _ProtocolBadge(protocol: provider.protocol),
          const SizedBox(height: 10),
          _KeyValueLine(label: 'Base URL', value: provider.baseUrl),
          FutureBuilder<List<ProviderModelInfo>>(
            future: loadModels(),
            builder: (context, snapshot) => _KeyValueLine(
              label: '模型数',
              value: snapshot.data == null ? '…' : '${snapshot.data!.length}',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _SmallIconButton(
                tooltip: '编辑',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
              _SmallIconButton(
                tooltip: '模型管理',
                icon: Icons.view_list_outlined,
                onPressed: onManageModels,
              ),
              _SmallIconButton(
                tooltip: '测试连通',
                icon: Icons.network_check_rounded,
                onPressed: onTest,
              ),
              _SmallIconButton(
                tooltip: '删除',
                icon: Icons.delete_outline_rounded,
                color: context.df.red,
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onManageModels;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _ProviderActions({
    required this.onEdit,
    required this.onManageModels,
    required this.onTest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SmallIconButton(
          tooltip: '编辑',
          icon: Icons.edit_outlined,
          onPressed: onEdit,
        ),
        _SmallIconButton(
          tooltip: '模型管理',
          icon: Icons.view_list_outlined,
          onPressed: onManageModels,
        ),
        _SmallIconButton(
          tooltip: '测试连通',
          icon: Icons.network_check_rounded,
          onPressed: onTest,
        ),
        _SmallIconButton(
          tooltip: '删除',
          icon: Icons.delete_outline_rounded,
          color: context.df.red,
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  const _SmallIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 19, color: color),
      onPressed: onPressed,
    );
  }
}

class _ProtocolBadge extends StatelessWidget {
  final String protocol;

  const _ProtocolBadge({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (protocol) {
      'volcengine' => ('火山引擎', context.df.red),
      _ => ('OpenAI兼容', context.df.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProviderFormResult {
  final String name;
  final String protocol;
  final String baseUrl;
  final String apiKey;

  const _ProviderFormResult({
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
  });
}

class _ProviderFormDialog extends StatefulWidget {
  final ProviderInfo? provider;

  const _ProviderFormDialog({this.provider});

  @override
  State<_ProviderFormDialog> createState() => _ProviderFormDialogState();
}

class _ProviderFormDialogState extends State<_ProviderFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late String _protocol;

  bool get _editing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _name = TextEditingController(text: provider?.name ?? '');
    _baseUrl = TextEditingController(text: provider?.baseUrl ?? '');
    _apiKey = TextEditingController(text: provider?.apiKey ?? '');
    _protocol = provider?.protocol ?? 'openai_compatible';
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? '编辑供应商' : '添加供应商'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                selected: {_protocol},
                segments: const [
                  ButtonSegment(
                    value: 'openai_compatible',
                    label: Text('OpenAI兼容'),
                  ),
                  ButtonSegment(
                    value: 'volcengine',
                    label: Text('火山引擎'),
                  ),
                ],
                onSelectionChanged: _editing
                    ? null
                    : (value) => setState(() => _protocol = value.single),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '名称',
                  hintText: _editing ? '留空不修改' : '例如：azt',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrl,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: _editing ? '留空不修改' : 'https://...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (!_editing && name.isEmpty) return;
            Navigator.of(context).pop(_ProviderFormResult(
              name: name,
              protocol: _protocol,
              baseUrl: _baseUrl.text.trim(),
              apiKey: _apiKey.text,
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ProviderModelsEditor extends ConsumerStatefulWidget {
  final ProviderInfo provider;
  final List<ProviderModelInfo> models;

  const _ProviderModelsEditor({
    required this.provider,
    required this.models,
  });

  @override
  ConsumerState<_ProviderModelsEditor> createState() =>
      _ProviderModelsEditorState();
}

class _ProviderModelsEditorState extends ConsumerState<_ProviderModelsEditor> {
  final List<_ModelDraft> _drafts = [];

  @override
  void initState() {
    super.initState();
    for (final model in widget.models) {
      _drafts.add(_ModelDraft.fromModel(model));
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _addModel() {
    setState(() => _drafts.add(_ModelDraft.empty()));
  }

  void _removeModel(_ModelDraft draft) {
    setState(() => _drafts.remove(draft));
    draft.dispose();
  }

  Future<void> _save() async {
    for (final draft in _drafts) {
      if (draft.modelId.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模型 ID 不能为空')),
        );
        return;
      }
    }

    final payload = [
      for (final draft in _drafts)
        {
          if (draft.id.isNotEmpty) 'id': draft.id,
          'modelId': draft.modelId.text.trim(),
          'label': draft.label.text.trim().isEmpty
              ? draft.modelId.text.trim()
              : draft.label.text.trim(),
          'kind': draft.kind,
          'capabilities': draft.capabilities,
          'enabled': draft.enabled,
        }
    ];

    await runAction(context, ref, () async {
      await ref
          .read(engineProvider)
          .saveProviderModels(widget.provider.id, payload);
    }, successMessage: '模型已保存');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return Scaffold(
      appBar: AppBar(
        title: Text('模型管理 · ${widget.provider.name}'),
        actions: [
          TextButton.icon(
            onPressed: _addModel,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加模型'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: PageContainer(
        maxWidth: 1040,
        child: ListView(
          children: [
            const SizedBox(height: 16),
            if (_drafts.isEmpty)
              EmptyHint(
                icon: Icons.view_list_outlined,
                title: '还没有模型',
                subtitle: '添加至少一个文本、图片、视频或配音模型',
                action: FilledButton.icon(
                  onPressed: _addModel,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加模型'),
                ),
              )
            else if (wide)
              _ModelsTable(
                drafts: _drafts,
                onChanged: () => setState(() {}),
                onRemove: _removeModel,
              )
            else
              Column(
                children: [
                  for (final draft in _drafts)
                    _ModelDraftCard(
                      draft: draft,
                      onChanged: () => setState(() {}),
                      onRemove: () => _removeModel(draft),
                    ),
                ],
              ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _ModelDraft {
  final String id;
  final TextEditingController modelId;
  final TextEditingController label;
  final Map<String, dynamic> capabilities;
  String kind;
  bool enabled;

  _ModelDraft({
    required this.id,
    required this.modelId,
    required this.label,
    required this.kind,
    required this.capabilities,
    required this.enabled,
  });

  factory _ModelDraft.fromModel(ProviderModelInfo model) => _ModelDraft(
        id: model.id,
        modelId: TextEditingController(text: model.modelId),
        label: TextEditingController(text: model.label),
        kind: model.kind,
        capabilities: model.capabilities,
        enabled: model.enabled,
      );

  factory _ModelDraft.empty() => _ModelDraft(
        id: '',
        modelId: TextEditingController(),
        label: TextEditingController(),
        kind: 'text',
        capabilities: const {},
        enabled: true,
      );

  void dispose() {
    modelId.dispose();
    label.dispose();
  }
}

class _ModelsTable extends StatelessWidget {
  final List<_ModelDraft> drafts;
  final VoidCallback onChanged;
  final ValueChanged<_ModelDraft> onRemove;

  const _ModelsTable({
    required this.drafts,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: context.df.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: context.df.stroke)),
            ),
            child: const Row(
              children: [
                _HeaderFlexCell(flex: 18, label: 'Model ID'),
                _HeaderFlexCell(flex: 18, label: 'Label'),
                _HeaderCell(width: 132, label: '类型'),
                _HeaderCell(width: 92, label: '启用'),
                _HeaderCell(width: 64, label: ''),
              ],
            ),
          ),
          for (final draft in drafts)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.df.stroke)),
              ),
              child: Row(
                children: [
                  _FormFlexCell(
                    flex: 18,
                    child: TextField(
                      controller: draft.modelId,
                      decoration: const InputDecoration(labelText: 'Model ID'),
                    ),
                  ),
                  _FormFlexCell(
                    flex: 18,
                    child: TextField(
                      controller: draft.label,
                      decoration: const InputDecoration(labelText: 'Label'),
                    ),
                  ),
                  _FixedCell(
                    width: 132,
                    child: DropdownButtonFormField<String>(
                      initialValue: _validKind(draft.kind),
                      decoration: const InputDecoration(labelText: '类型'),
                      items: [
                        for (final kind in _modelKinds)
                          DropdownMenuItem(
                            value: kind.value,
                            child: Text(kind.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        draft.kind = value;
                        onChanged();
                      },
                    ),
                  ),
                  _FixedCell(
                    width: 92,
                    child: Switch(
                      value: draft.enabled,
                      onChanged: (value) {
                        draft.enabled = value;
                        onChanged();
                      },
                    ),
                  ),
                  _FixedCell(
                    width: 64,
                    child: IconButton(
                      tooltip: '删除模型',
                      icon: Icon(Icons.delete_outline_rounded,
                          color: context.df.red),
                      onPressed: () => onRemove(draft),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelDraftCard extends StatelessWidget {
  final _ModelDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ModelDraftCard({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        children: [
          TextField(
            controller: draft.modelId,
            decoration: const InputDecoration(labelText: 'Model ID'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.label,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _validKind(draft.kind),
                  decoration: const InputDecoration(labelText: '类型'),
                  items: [
                    for (final kind in _modelKinds)
                      DropdownMenuItem(
                        value: kind.value,
                        child: Text(kind.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    draft.kind = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: draft.enabled,
                onChanged: (value) {
                  draft.enabled = value;
                  onChanged();
                },
              ),
              IconButton(
                tooltip: '删除模型',
                icon: Icon(Icons.delete_outline_rounded, color: context.df.red),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _validKind(String kind) =>
    _modelKinds.any((item) => item.value == kind) ? kind : 'text';

class _ModelOption {
  final ProviderInfo provider;
  final ProviderModelInfo model;

  const _ModelOption({required this.provider, required this.model});

  String get kind => model.kind;
  String get value => '${provider.id}:${model.modelId}';
  String get label => '${provider.name} · ${_modelLabel(model)}';
}

class _BindingRow extends StatelessWidget {
  final _StageMeta stage;
  final String? binding;
  final List<_ModelOption> options;
  final ValueChanged<String> onChanged;

  const _BindingRow({
    required this.stage,
    required this.binding,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final optionValues = options.map((option) => option.value).toSet();
    final current =
        binding != null && optionValues.contains(binding) ? binding : null;
    final missing = current == null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 680;
          final title = _BindingTitle(stage: stage, missing: missing);
          final picker = _BindingPicker(
            current: current,
            options: options,
            missing: missing,
            onChanged: onChanged,
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 10),
                picker,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: title),
              const SizedBox(width: 18),
              Expanded(flex: 4, child: picker),
            ],
          );
        },
      ),
    );
  }
}

class _BindingTitle extends StatelessWidget {
  final _StageMeta stage;
  final bool missing;

  const _BindingTitle({required this.stage, required this.missing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stage.title,
                style: TextStyle(
                  color: context.df.textHi,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _KindBadge(kind: stage.kind),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          stage.description,
          style: TextStyle(color: context.df.textLo, fontSize: 12),
        ),
        if (missing) ...[
          const SizedBox(height: 6),
          Text(
            '未绑定可用模型',
            style: TextStyle(
              color: context.df.red,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _BindingPicker extends StatelessWidget {
  final String? current;
  final List<_ModelOption> options;
  final bool missing;
  final ValueChanged<String> onChanged;

  const _BindingPicker({
    required this.current,
    required this.options,
    required this.missing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '绑定模型',
        errorText: missing ? '请选择启用模型' : null,
      ),
      hint: const Text('选择模型'),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: options.isEmpty
          ? null
          : (value) {
              if (value != null && value != current) onChanged(value);
            },
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;

  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final label = _modelKinds
        .firstWhere(
          (item) => item.value == kind,
          orElse: () => const _KindMeta('text', '文本'),
        )
        .label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.df.primaryDim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.df.primary.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.df.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PromptRow extends StatelessWidget {
  final _PromptMeta meta;
  final Map<String, dynamic>? prompt;
  final VoidCallback onOpen;

  const _PromptRow({
    required this.meta,
    required this.prompt,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final content = (prompt?['content'] ?? '').toString();
    final updatedAt = (prompt?['updatedAt'] ?? '').toString();
    final preview = content.trim().replaceAll('\n', ' ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.df.stroke)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      style: TextStyle(
                        color: context.df.textHi,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta.description,
                      style: TextStyle(color: context.df.textLo, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview.isEmpty ? '未设置' : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: preview.isEmpty
                            ? context.df.textLo
                            : context.df.textMid,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${content.length} 字符${updatedAt.isEmpty ? '' : ' · $updatedAt'}',
                      style: TextStyle(color: context.df.textLo, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: context.df.textLo),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptEditorPage extends ConsumerStatefulWidget {
  final _PromptMeta meta;
  final String initialContent;

  const _PromptEditorPage({
    required this.meta,
    required this.initialContent,
  });

  @override
  ConsumerState<_PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends ConsumerState<_PromptEditorPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await runAction(context, ref, () async {
      await ref
          .read(engineProvider)
          .updatePrompt(widget.meta.key, _controller.text);
    }, successMessage: '提示词已保存');
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置为默认'),
        content: Text('确定将“${widget.meta.title}”恢复为内置默认内容吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).resetPrompt(widget.meta.key);
    }, successMessage: '提示词已重置');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('编辑提示词 · ${widget.meta.title}'),
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('重置为默认'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: PageContainer(
        maxWidth: 1040,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: context.df.textHi,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: '提示词内容',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Text(
                  '${_controller.text.length} 字符',
                  style: TextStyle(color: context.df.textLo, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final double width;
  final String label;

  const _HeaderCell({required this.width, required this.label});

  @override
  Widget build(BuildContext context) {
    return _FixedCell(
      width: width,
      child: Text(
        label,
        style: TextStyle(
          color: context.df.textLo,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderFlexCell extends StatelessWidget {
  final int flex;
  final String label;

  const _HeaderFlexCell({required this.flex, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          style: TextStyle(
            color: context.df.textLo,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FixedCell extends StatelessWidget {
  final double width;
  final Widget child;

  const _FixedCell({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: child,
      ),
    );
  }
}

class _TextFlexCell extends StatelessWidget {
  final int flex;
  final String text;
  final String emptyText;
  final String? tooltip;
  final TextStyle? style;

  const _TextFlexCell({
    required this.flex,
    required this.text,
    this.emptyText = '—',
    this.tooltip,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty ? emptyText : text;
    final content = Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ??
          TextStyle(
            color: text.trim().isEmpty ? context.df.textLo : context.df.textMid,
            fontSize: 13,
          ),
    );
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: tooltip == null || tooltip!.isEmpty
            ? content
            : Tooltip(message: tooltip!, child: content),
      ),
    );
  }
}

class _FormFlexCell extends StatelessWidget {
  final int flex;
  final Widget child;

  const _FormFlexCell({required this.flex, required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: child,
      ),
    );
  }
}

class _KeyValueLine extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValueLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(color: context.df.textLo, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '未设置' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value.isEmpty ? context.df.textLo : context.df.textMid,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
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

String _modelLabel(ProviderModelInfo model) =>
    model.label.trim().isEmpty ? model.modelId : model.label;
