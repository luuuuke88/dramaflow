import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../engine/db_admin.dart';
import '../engine/provider_presets.dart';
import '../engine/util.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../util/l10n_ext.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'provider_preset_form.dart';
import 'provider_preset_gallery.dart';

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

// 应用版本（对齐 pubspec version；package_info_plus 未引入，引擎版本另经 health 展示）。
const _appVersion = '0.1.0';

Future<void> Function(String path)? debugOpenDataFolderOverride;

enum _SettingsSection {
  appearance,
  providers,
  bindings,
  prompts,
  other,
  storage,
  about,
}

String _sectionLabel(AppLocalizations l10n, _SettingsSection section) =>
    switch (section) {
      _SettingsSection.appearance => l10n.settingsAppearanceSection,
      _SettingsSection.providers => l10n.settingsProvidersSection,
      _SettingsSection.bindings => l10n.settingsBindingsSection,
      _SettingsSection.prompts => l10n.settingsPromptsSection,
      _SettingsSection.other => l10n.settingsOtherSection,
      _SettingsSection.storage => l10n.settingsStorageSection,
      _SettingsSection.about => l10n.settingsAboutSection,
    };

const _sectionIcons = {
  _SettingsSection.appearance: Icons.palette_outlined,
  _SettingsSection.providers: Icons.cloud_queue_rounded,
  _SettingsSection.bindings: Icons.hub_outlined,
  _SettingsSection.prompts: Icons.article_outlined,
  _SettingsSection.other: Icons.tune_rounded,
  _SettingsSection.storage: Icons.storage_outlined,
  _SettingsSection.about: Icons.info_outline_rounded,
};

const _stages = [
  _StageMeta('script_gen', 'text'),
  _StageMeta('event_extract', 'text'),
  _StageMeta('asset_extract', 'text'),
  _StageMeta('director_plan', 'text'),
  _StageMeta('storyboard_table', 'text'),
  _StageMeta('storyboard_gen', 'text'),
  _StageMeta('video_prompt_gen', 'text'),
  _StageMeta('asset_image', 'image'),
  _StageMeta('shot_image', 'image'),
  _StageMeta('shot_video', 'video'),
  _StageMeta('tts', 'tts'),
];

const _promptMetas = [
  _PromptMeta('scriptGen'),
  _PromptMeta('eventExtraction'),
  _PromptMeta('scriptAssetExtraction'),
  _PromptMeta('director_plan'),
  _PromptMeta('storyboard_table'),
  _PromptMeta('storyboard_gen'),
  _PromptMeta('video_prompt_gen'),
  _PromptMeta('audio_bind'),
  _PromptMeta('eventAnalysis'),
  _PromptMeta('image_size_directive'),
];

const _modelKinds = [
  _KindMeta('text'),
  _KindMeta('image'),
  _KindMeta('video'),
  _KindMeta('tts'),
];

class _StageMeta {
  final String key;
  final String kind;

  const _StageMeta(this.key, this.kind);

  String title(AppLocalizations l10n) => switch (key) {
        'script_gen' => l10n.stageScriptGenTitle,
        'event_extract' => l10n.stageEventExtractTitle,
        'asset_extract' => l10n.stageAssetExtractTitle,
        'storyboard_gen' => l10n.stageStoryboardGenTitle,
        'video_prompt_gen' => l10n.stageVideoPromptGenTitle,
        'asset_image' => l10n.stageAssetImageTitle,
        'shot_image' => l10n.stageShotImageTitle,
        'shot_video' => l10n.stageShotVideoTitle,
        'tts' => l10n.stageTtsTitle,
        _ => key,
      };

  String description(AppLocalizations l10n) => switch (key) {
        'script_gen' => l10n.stageScriptGenDescription,
        'event_extract' => l10n.stageEventExtractDescription,
        'asset_extract' => l10n.stageAssetExtractDescription,
        'storyboard_gen' => l10n.stageStoryboardGenDescription,
        'video_prompt_gen' => l10n.stageVideoPromptGenDescription,
        'asset_image' => l10n.stageAssetImageDescription,
        'shot_image' => l10n.stageShotImageDescription,
        'shot_video' => l10n.stageShotVideoDescription,
        'tts' => l10n.stageTtsDescription,
        _ => '',
      };
}

class _PromptMeta {
  final String key;

  const _PromptMeta(this.key);

  String title(AppLocalizations l10n) => switch (key) {
        'scriptGen' => l10n.stageScriptGenTitle,
        'eventExtraction' => l10n.promptEventExtractionTitle,
        'scriptAssetExtraction' => l10n.promptScriptAssetExtractionTitle,
        'storyboard_gen' => l10n.promptStoryboardGenTitle,
        'video_prompt_gen' => l10n.promptVideoPromptGenTitle,
        'audio_bind' => l10n.promptAudioBindTitle,
        'eventAnalysis' => l10n.promptEventAnalysisTitle,
        'image_size_directive' => l10n.promptImageSizeDirectiveTitle,
        _ => key,
      };

  String description(AppLocalizations l10n) => switch (key) {
        'scriptGen' => l10n.stageScriptGenDescription,
        'eventExtraction' => l10n.promptEventExtractionDescription,
        'scriptAssetExtraction' => l10n.promptScriptAssetExtractionDescription,
        'storyboard_gen' => l10n.promptStoryboardGenDescription,
        'video_prompt_gen' => l10n.promptVideoPromptGenDescription,
        'audio_bind' => l10n.promptAudioBindDescription,
        'eventAnalysis' => l10n.promptEventAnalysisDescription,
        'image_size_directive' => l10n.promptImageSizeDirectiveDescription,
        _ => '',
      };
}

class _KindMeta {
  final String value;

  const _KindMeta(this.value);

  String label(AppLocalizations l10n) => switch (value) {
        'text' => l10n.modelKindText,
        'image' => l10n.modelKindImage,
        'video' => l10n.modelKindVideo,
        'tts' => l10n.modelKindTts,
        'embedding' => l10n.modelKindEmbedding,
        _ => value,
      };
}

/// 设置页：M2 配置后台（供应商 / 模型绑定 / 提示词）+ 外观与本机存储。
class SettingsScreen extends ConsumerStatefulWidget {
  /// 可由首次引导等上下文直接定位到既有分区；未知值安全回落到外观。
  final String? initialSection;

  /// 首次引导中的设置入口提供明确返回，不影响普通设置页导航。
  final bool showOnboardingReturn;

  const SettingsScreen({
    super.key,
    this.initialSection,
    this.showOnboardingReturn = false,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.appearance;
  int _modelRevision = 0;

  // 其他设置字段控制器（懒初始化：进入面板时按引擎当前值填充）。
  TextEditingController? _chapterRegCtrl;
  TextEditingController? _episodeLengthCtrl;
  TextEditingController? _batchSizeCtrl;

  @override
  void initState() {
    super.initState();
    _section = switch (widget.initialSection) {
      'providers' => _SettingsSection.providers,
      'bindings' => _SettingsSection.bindings,
      'prompts' => _SettingsSection.prompts,
      'other' => _SettingsSection.other,
      'storage' => _SettingsSection.storage,
      'about' => _SettingsSection.about,
      _ => _SettingsSection.appearance,
    };
  }

  void _ensureOtherControllers() {
    if (_chapterRegCtrl != null) return;
    final config = ref.read(engineProvider).config;
    _chapterRegCtrl = TextEditingController(text: config.str('chapterReg'));
    _episodeLengthCtrl =
        TextEditingController(text: config.str('scriptEpisodeLength'));
    _batchSizeCtrl =
        TextEditingController(text: config.str('assetsBatchGenereateSize'));
  }

  @override
  void dispose() {
    _chapterRegCtrl?.dispose();
    _episodeLengthCtrl?.dispose();
    _batchSizeCtrl?.dispose();
    super.dispose();
  }

  void _selectSection(_SettingsSection section) {
    if (section == _section) return;
    setState(() => _section = section);
  }

  void _invalidateConfig() {
    ref.invalidate(providersProvider);
    ref.invalidate(bindingsProvider);
    ref.invalidate(promptsProvider);
    ref.invalidate(modelPromptsProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(healthProvider);
    setState(() => _modelRevision++);
  }

  void _invalidateProvidersAndBindings() {
    ref.invalidate(providersProvider);
    ref.invalidate(bindingsProvider);
    ref.invalidate(modelPromptsProvider);
    ref.invalidate(healthProvider);
    setState(() => _modelRevision++);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _lightAppBarBackground(context),
        bottom: _lightAppBarBottom(context),
        leading: widget.showOnboardingReturn
            ? IconButton(
                key: const Key('onboarding-return'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/onboarding'),
              )
            : null,
        title: Text(l10n.settingsTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
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
          _SettingsSection.appearance => Column(children: [
              _appearanceCard(),
              const SizedBox(height: 12),
              _languageCard(),
            ]),
          _SettingsSection.providers => KeyedSubtree(
              key: const Key('settings-section-providers'),
              child: _providersPanel(),
            ),
          _SettingsSection.bindings => KeyedSubtree(
              key: const Key('settings-section-bindings'),
              child: _bindingsPanel(),
            ),
          _SettingsSection.prompts => _promptsPanel(),
          _SettingsSection.other => _otherPanel(),
          _SettingsSection.storage => _storageCard(),
          _SettingsSection.about => _aboutCard(),
        },
        const SizedBox(height: 40),
      ],
    );
  }

  // ---------- 0. 外观 ----------

  Widget _appearanceCard() {
    final themeMode = ref.watch(themeModeProvider);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.settingsAppearanceSection,
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
        segments: [
          ButtonSegment(
            value: ThemeMode.light,
            icon: const Icon(Icons.light_mode_outlined, size: 18),
            label: Text(l10n.settingsThemeLight),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: const Icon(Icons.dark_mode_outlined, size: 18),
            label: Text(l10n.settingsThemeDark),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: const Icon(Icons.brightness_auto_outlined, size: 18),
            label: Text(l10n.settingsThemeSystem),
          ),
        ],
        selected: {themeMode},
        onSelectionChanged: (selected) {
          final next = selected.single;
          if (next == themeMode) return;
          runAction(context, ref, () async {
            await ref.read(themeModeProvider.notifier).setThemeMode(next);
          }, successMessage: l10n.settingsThemeUpdated);
        },
      ),
    );
  }

  Widget _languageCard() {
    final locale = ref.watch(localeProvider);
    final l10n = AppLocalizations.of(context);
    final current = locale?.languageCode ?? '';
    return _SettingsCard(
      title: l10n.settingsLanguage,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: '', label: Text(l10n.localeSystem)),
          ButtonSegment(value: 'zh', label: Text(l10n.localeChinese)),
          const ButtonSegment(value: 'en', label: Text('English')),
          ButtonSegment(value: 'ja', label: Text(l10n.localeJapanese)),
        ],
        selected: {current},
        onSelectionChanged: (selected) {
          final next = selected.single;
          if (next == current) return;
          runAction(context, ref, () async {
            await ref
                .read(localeProvider.notifier)
                .setLocale(next.isEmpty ? null : Locale(next));
          }, successMessage: l10n.settingsLanguage);
        },
      ),
    );
  }

  // ---------- 1. 供应商 ----------

  Widget _providersPanel() {
    final providersAsync = ref.watch(providersProvider);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.settingsProvidersSection,
      trailing: FilledButton.icon(
        onPressed: _openCreateProviderDialog,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(l10n.settingsAddProvider),
      ),
      child: AsyncView<List<ProviderInfo>>(
        value: providersAsync,
        onRetry: () => ref.invalidate(providersProvider),
        builder: (providers) {
          if (providers.isEmpty) {
            return EmptyHint(
              icon: Icons.cloud_off_outlined,
              title: l10n.settingsProviderEmptyTitle,
              subtitle: l10n.settingsProviderEmptySubtitle,
              action: FilledButton.icon(
                onPressed: _openCreateProviderDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.settingsAddProvider),
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
    final providers = await ref.read(engineProvider).listProviders();
    if (!mounted) return;
    final picked = await showProviderPresetGallery(context,
        existingProviderIds: {for (final p in providers) p.id});
    if (picked == null || !mounted) return;

    if (picked == 'custom') {
      final result = await showDialog<_ProviderFormResult>(
        context: context,
        builder: (_) => const _ProviderFormDialog(),
      );
      if (result == null || !mounted) return;
      final l10n = context.l10n;
      await runAction(context, ref, () async {
        await ref.read(engineProvider).createProvider(
              name: result.name,
              protocol: result.protocol,
              baseUrl: result.baseUrl,
              apiKey: result.apiKey,
            );
      }, successMessage: l10n.settingsProviderAdded);
      if (!mounted) return;
      _invalidateProvidersAndBindings();
      return;
    }

    final existing = providers.where((p) => p.id == picked).toList();
    if (existing.isNotEmpty) {
      await _openEditProviderDialog(existing.first);
      return;
    }

    final created =
        await showProviderPresetForm(context, ref, presetId: picked);
    if (created && mounted) _invalidateProvidersAndBindings();
  }

  Future<void> _openEditProviderDialog(ProviderInfo provider) async {
    final result = await showDialog<_ProviderFormResult>(
      context: context,
      builder: (_) => _ProviderFormDialog(provider: provider),
    );
    if (result == null || !mounted) return;
    final l10n = context.l10n;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateProvider(
            provider.id,
            name: result.name.isEmpty ? null : result.name,
            baseUrl: result.baseUrl.isEmpty ? null : result.baseUrl,
            apiKey: result.apiKey.isEmpty ? null : result.apiKey,
          );
    }, successMessage: l10n.settingsProviderUpdated);
    if (!mounted) return;
    _invalidateProvidersAndBindings();
  }

  Future<void> _setProviderEnabled(ProviderInfo provider, bool enabled) async {
    final l10n = context.l10n;
    await runAction(context, ref, () async {
      final data = await ref.read(engineProvider).exportConfig();
      final providers = data['providers'];
      if (providers is! List) {
        throw EngineException(l10n.settingsProviderConfigMissing);
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
      if (!changed) throw EngineException(l10n.settingsProviderMissing);
      await ref.read(engineProvider).importConfig(data);
    },
        successMessage: enabled
            ? l10n.settingsProviderEnabled
            : l10n.settingsProviderDisabled);
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

    // 分模态测试（对齐引擎 testProvider 的 text/image/video 分派）：
    // 允许测试任一启用的文本/图片/视频模型，而非仅文本。
    final testable = models!
        .where((model) =>
            model.enabled &&
            const {'text', 'image', 'video', 'tts'}.contains(model.kind))
        .toList();
    if (testable.isEmpty) {
      await runAction(context, ref, () async {
        throw EngineException(context.l10n.settingsProviderTestNoModel);
      });
      return;
    }

    final selected = testable.length == 1
        ? testable.first
        : await _chooseTestModel(provider, testable);
    if (!mounted || selected == null) return;

    var elapsedMs = 0;
    final l10n = context.l10n;
    await runAction(context, ref, () async {
      elapsedMs = await ref
          .read(engineProvider)
          .testProvider(provider.id, selected.modelId);
    }, successMessage: l10n.settingsProviderTestSuccess(elapsedMs));
  }

  Future<ProviderModelInfo?> _chooseTestModel(
      ProviderInfo provider, List<ProviderModelInfo> models) {
    final l10n = context.l10n;
    var selected = models.first;
    String kindLabel(String kind) => _modelKinds
        .firstWhere((item) => item.value == kind,
            orElse: () => const _KindMeta('text'))
        .label(l10n);
    return showDialog<ProviderModelInfo>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.settingsProviderTestTitle(provider.name)),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<ProviderModelInfo>(
              initialValue: selected,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: l10n.settingsProviderTestKind),
              items: [
                for (final model in models)
                  DropdownMenuItem(
                    value: model,
                    child: Text(
                      '${kindLabel(model.kind)} · ${_modelLabel(model)}',
                      overflow: TextOverflow.ellipsis,
                    ),
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
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(l10n.commonTest),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProvider(ProviderInfo provider) async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.settingsDeleteProviderTitle,
      message: l10n.settingsDeleteProviderMessage(provider.name),
      confirmText: l10n.commonDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).deleteProvider(provider.id);
    }, successMessage: l10n.settingsProviderDeleted);
    if (!mounted) return;
    _invalidateProvidersAndBindings();
  }

  // ---------- 2. 模型绑定 ----------

  Widget _bindingsPanel() {
    final providersAsync = ref.watch(providersProvider);
    final bindingsAsync = ref.watch(bindingsProvider);
    return _SettingsCard(
      title: context.l10n.settingsBindingsSection,
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

    final l10n = context.l10n;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).setBinding(stage.key, providerId, modelId);
    }, successMessage: l10n.stageBindingUpdated(stage.title(l10n)));
    if (!mounted) return;
    ref.invalidate(bindingsProvider);
    ref.invalidate(healthProvider);
  }

  // ---------- 3. 提示词 ----------

  Widget _promptsPanel() {
    final promptsAsync = ref.watch(promptsProvider);
    final modelPromptsAsync = ref.watch(modelPromptsProvider);
    return _SettingsCard(
      title: context.l10n.promptPanelTitle,
      child: AsyncView<List<Map<String, dynamic>>>(
        value: promptsAsync,
        onRetry: () => ref.invalidate(promptsProvider),
        builder: (prompts) {
          final byKey = {
            for (final prompt in prompts)
              (prompt['key'] ?? '').toString(): prompt
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SubsectionTitle(label: context.l10n.promptGlobalTemplates),
              for (final meta in _promptMetas)
                _PromptRow(
                  meta: meta,
                  prompt: byKey[meta.key],
                  onOpen: () => _openPromptEditor(meta, byKey[meta.key]),
                ),
              const SizedBox(height: 18),
              _SubsectionTitle(label: context.l10n.promptModelTemplates),
              AsyncView<List<Map<String, dynamic>>>(
                value: modelPromptsAsync,
                onRetry: () => ref.invalidate(modelPromptsProvider),
                builder: (modelPrompts) => modelPrompts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          context.l10n.promptModelTemplatesEmpty,
                          style: TextStyle(color: context.df.textLo),
                        ),
                      )
                    : Column(
                        children: [
                          for (final prompt in modelPrompts)
                            _ModelPromptRow(
                              prompt: prompt,
                              onOpen: () => _openModelPromptEditor(prompt),
                            ),
                        ],
                      ),
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

  Future<void> _openModelPromptEditor(Map<String, dynamic> prompt) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ModelPromptEditorPage(prompt: prompt),
        fullscreenDialog: true,
      ),
    );
    if (saved == true && mounted) {
      ref.invalidate(modelPromptsProvider);
    }
  }

  // ---------- 4. 其他设置 ----------

  Widget _otherPanel() {
    _ensureOtherControllers();
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.settingsOtherTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _chapterRegCtrl,
            decoration: InputDecoration(
              labelText: l10n.settingsOtherChapterReg,
              helperText: l10n.settingsOtherChapterRegHint,
              suffixIcon: IconButton(
                tooltip: l10n.settingsOtherChapterRegRestore,
                icon: const Icon(Icons.restore_rounded, size: 18),
                onPressed: () => setState(() => _chapterRegCtrl!.clear()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _episodeLengthCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.settingsOtherEpisodeLength,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _batchSizeCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.settingsOtherBatchSize,
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saveOtherSettings,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(l10n.commonSave),
            ),
          ),
          const Divider(height: 28),
          SwitchListTile(
            key: const ValueKey('settings-policy-confirm-money-switch'),
            contentPadding: EdgeInsets.zero,
            value: ref.read(engineProvider).config.str('policy.confirmMoney') !=
                '0',
            onChanged: (v) => setState(() {
              ref
                  .read(engineProvider)
                  .config
                  .update({'policy.confirmMoney': v ? '1' : '0'});
            }),
            title: Text(l10n.settingsPolicyConfirmMoney),
          ),
          SwitchListTile(
            key: const ValueKey('settings-policy-confirm-destructive-switch'),
            contentPadding: EdgeInsets.zero,
            value: ref
                    .read(engineProvider)
                    .config
                    .str('policy.confirmDestructive') !=
                '0',
            onChanged: (v) => setState(() {
              ref
                  .read(engineProvider)
                  .config
                  .update({'policy.confirmDestructive': v ? '1' : '0'});
            }),
            title: Text(l10n.settingsPolicyConfirmDestructive),
          ),
        ],
      ),
    );
  }

  Future<void> _saveOtherSettings() async {
    final l10n = context.l10n;
    final episode = int.tryParse(_episodeLengthCtrl!.text.trim());
    final batch = int.tryParse(_batchSizeCtrl!.text.trim());
    if (episode == null || episode <= 0 || batch == null || batch <= 0) {
      await runAction(context, ref, () async {
        throw EngineException(l10n.settingsOtherInvalidNumber);
      });
      return;
    }
    await runAction(context, ref, () async {
      ref.read(engineProvider).config.update({
        'chapterReg': _chapterRegCtrl!.text.trim(),
        'scriptEpisodeLength': '$episode',
        'assetsBatchGenereateSize': '$batch',
      });
    }, successMessage: l10n.settingsOtherSaved);
  }

  // ---------- 5. 存储与引擎 ----------

  Widget _storageCard() {
    final engine = ref.read(engineProvider);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.settingsStorageSection,
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
                label: Text(l10n.settingsExportConfig),
              ),
              OutlinedButton.icon(
                onPressed: _importConfig,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(l10n.settingsImportConfig),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsConfigPlaintextWarning,
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
            l10n.settingsEmbeddedEngineNote,
            style: TextStyle(color: context.df.textLo, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openDataFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(context.l10n.settingsStorageOpenFolder),
              ),
              OutlinedButton.icon(
                onPressed: _showDbInfo,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: Text(context.l10n.settingsStorageDbInfo),
              ),
              OutlinedButton.icon(
                onPressed: _clearAllData,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.df.red,
                  side:
                      BorderSide(color: context.df.red.withValues(alpha: 0.5)),
                ),
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: Text(context.l10n.settingsStorageClear),
              ),
            ],
          ),
          const Divider(height: 28),
          Text(l10n.settingsEngineStatus,
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
      final l10n = context.l10n;
      await runAction(context, ref, () async {
        throw EngineException(l10n.settingsExportPanelFailed('$e'));
      });
      return;
    }
    if (!mounted || location == null) return;
    final l10n = context.l10n;

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
        throw EngineException(l10n.settingsExportFailed('$e'));
      }
    }, successMessage: l10n.settingsConfigExported);
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
      final l10n = context.l10n;
      await runAction(context, ref, () async {
        throw EngineException(l10n.settingsOpenFileFailed('$e'));
      });
      return;
    }
    if (!mounted || file == null) return;
    final l10n = context.l10n;

    final confirmed = await _confirm(
      title: l10n.settingsImportConfigTitle,
      message: l10n.settingsImportConfigMessage,
      confirmText: l10n.settingsImportConfig,
    );
    if (!mounted || !confirmed) return;

    await runAction(context, ref, () async {
      try {
        final raw = await file!.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw EngineException(l10n.settingsConfigInvalidFormat);
        }
        await ref
            .read(engineProvider)
            .importConfig(Map<String, dynamic>.from(decoded));
      } on FormatException {
        throw EngineException(l10n.settingsConfigInvalidJson);
      } on EngineException {
        rethrow;
      } catch (e) {
        throw EngineException(l10n.settingsImportFailed('$e'));
      }
    }, successMessage: l10n.settingsConfigImported);
    if (!mounted) return;
    _invalidateConfig();
  }

  Future<void> _openDataFolder() async {
    final l10n = context.l10n;
    final dir = ref.read(engineProvider).dataDirPath();
    await runAction(context, ref, () async {
      try {
        final override = debugOpenDataFolderOverride;
        if (override != null) {
          await override(dir);
        } else if (Platform.isMacOS) {
          final result = await Process.run('open', [dir]);
          if (result.exitCode != 0) {
            throw EngineException(l10n.settingsStorageOpenFolderFailed(
                (result.stderr ?? '').toString().trim()));
          }
        } else {
          final ok = await launchUrl(Uri.file(dir));
          if (!ok) {
            throw EngineException(l10n.settingsStorageOpenFolderFailed(dir));
          }
        }
      } on EngineException {
        rethrow;
      } catch (e) {
        throw EngineException(l10n.settingsStorageOpenFolderFailed('$e'));
      }
    });
  }

  Future<void> _showDbInfo() async {
    final l10n = context.l10n;
    final info = ref.read(engineProvider).dbInfo();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsStorageDbInfoTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l10n.settingsStorageTableColumn,
                            style: TextStyle(
                                color: context.df.textLo,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      Text(l10n.settingsStorageRowsColumn,
                          style: TextStyle(
                              color: context.df.textLo,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                for (final row in info)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(row.table,
                              style: TextStyle(
                                  color: context.df.textMid,
                                  fontSize: 13,
                                  fontFamily: 'monospace')),
                        ),
                        Text('${row.rowCount}',
                            style: TextStyle(
                                color: context.df.textHi,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.settingsStorageClearConfirmTitle,
      message: l10n.settingsStorageClearConfirmBody,
      confirmText: l10n.settingsStorageClear,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await runAction(context, ref, () async {
      ref.read(engineProvider).clearAllData();
    }, successMessage: l10n.settingsStorageClearDone);
    if (!mounted) return;
    ref.invalidate(projectsProvider);
    _invalidateConfig();
  }

  // ---------- 6. 关于 ----------

  Widget _aboutCard() {
    final l10n = context.l10n;
    final health = ref.watch(healthProvider);
    final engineVersion = health.value?['version']?.toString() ?? '—';
    return _SettingsCard(
      title: l10n.settingsAboutTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValueLine(label: l10n.settingsAboutAppName, value: 'DramaFlow'),
          _KeyValueLine(label: l10n.settingsAboutVersion, value: _appVersion),
          _KeyValueLine(label: l10n.settingsAboutEngine, value: engineVersion),
          const SizedBox(height: 12),
          Text(
            l10n.settingsAboutDescription,
            style:
                TextStyle(color: context.df.textLo, fontSize: 12, height: 1.5),
          ),
        ],
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
          Text(context.l10n.settingsEngineChecking,
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
            label: Text(context.l10n.commonRetry),
            onPressed: () => ref.invalidate(healthProvider),
          ),
        ],
      ),
      data: (d) {
        final providers =
            (d['providers'] as Map?)?.cast<String, dynamic>() ?? const {};
        final labels = [
          ('text', context.l10n.modelKindText),
          ('image', context.l10n.modelKindImage),
          ('video', context.l10n.modelKindVideo),
          ('embedding', context.l10n.modelKindEmbedding),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Dot(color: context.df.green),
                const SizedBox(width: 8),
                Text(
                  context.l10n.settingsEngineOk('${d['version'] ?? '?'}'),
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
                        '${providers[key] ?? context.l10n.settingsEngineUnknown}',
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
            child: Text(context.l10n.commonCancel),
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
    final l10n = context.l10n;
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
            for (final section in _SettingsSection.values)
              ButtonSegment(
                value: section,
                icon: Icon(_sectionIcons[section], size: 18),
                label: Text(_sectionLabel(l10n, section)),
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
          for (final section in _SettingsSection.values)
            _SideNavItem(
              section: section,
              selected: selected == section,
              onTap: () => onSelected(section),
            ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.section,
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
                Icon(_sectionIcons[section], size: 19, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _sectionLabel(context.l10n, section),
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
    final l10n = context.l10n;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.df.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: Row(
        children: [
          _HeaderFlexCell(flex: 14, label: l10n.commonName),
          _HeaderCell(width: 118, label: l10n.settingsProviderColumnProtocol),
          _HeaderFlexCell(flex: 24, label: l10n.settingsProviderColumnBaseUrl),
          _HeaderCell(width: 92, label: l10n.commonEnabled),
          _HeaderCell(width: 72, label: l10n.commonModel),
          _HeaderCell(width: 184, label: l10n.commonActions),
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
            emptyText: context.l10n.commonUnset,
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
              label: context.l10n.settingsModelCount,
              value: snapshot.data == null ? '…' : '${snapshot.data!.length}',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _SmallIconButton(
                tooltip: context.l10n.commonEdit,
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
              _SmallIconButton(
                tooltip: context.l10n.settingsManageModels,
                icon: Icons.view_list_outlined,
                onPressed: onManageModels,
              ),
              _SmallIconButton(
                tooltip: context.l10n.settingsTestConnection,
                icon: Icons.network_check_rounded,
                onPressed: onTest,
              ),
              _SmallIconButton(
                tooltip: context.l10n.commonDelete,
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

class _VideoCapabilityEditor extends StatelessWidget {
  final _ModelDraft draft;
  final VoidCallback onChanged;

  const _VideoCapabilityEditor({required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final id = draft.modelId.text.trim().isEmpty
        ? draft.id
        : draft.modelId.text.trim();
    return ExpansionTile(
      key: ValueKey('video-capability-$id'),
      title: Text(l10n.settingsVideoCapabilities),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final mode in _videoModeValues)
              FilterChip(
                key: ValueKey('video-capability-mode-$mode-$id'),
                label: Text(mode),
                selected: draft.videoModes.contains(mode),
                onSelected: (selected) {
                  if (selected) {
                    draft.videoModes.add(mode);
                  } else {
                    draft.videoModes.remove(mode);
                  }
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _capabilityInput(
                  draft.videoImageReferences,
                  ValueKey('video-capability-reference-image-$id'),
                  l10n.settingsVideoReferenceImage)),
          const SizedBox(width: 8),
          Expanded(
              child: _capabilityInput(
                  draft.videoReferences,
                  ValueKey('video-capability-reference-video-$id'),
                  l10n.settingsVideoReferenceVideo)),
          const SizedBox(width: 8),
          Expanded(
              child: _capabilityInput(
                  draft.audioReferences,
                  ValueKey('video-capability-reference-audio-$id'),
                  l10n.settingsVideoReferenceAudio)),
        ]),
        const SizedBox(height: 8),
        _capabilityInput(
            draft.videoDurations,
            ValueKey('video-capability-durations-$id'),
            l10n.settingsVideoDurations),
        const SizedBox(height: 8),
        _capabilityInput(
            draft.videoResolutions,
            ValueKey('video-capability-resolutions-$id'),
            l10n.settingsVideoResolutions),
        const SizedBox(height: 8),
        _capabilityInput(draft.videoRatios,
            ValueKey('video-capability-ratios-$id'), l10n.settingsVideoRatios),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('video-capability-audio-$id'),
          initialValue: draft.videoAudio,
          items: [
            DropdownMenuItem(
                value: 'none', child: Text(l10n.settingsVideoAudioNone)),
            DropdownMenuItem(
                value: 'optional',
                child: Text(l10n.settingsVideoAudioOptional)),
            DropdownMenuItem(
                value: 'required',
                child: Text(l10n.settingsVideoAudioRequired)),
          ],
          onChanged: (value) {
            if (value == null) return;
            draft.videoAudio = value;
            onChanged();
          },
        ),
        for (final mode in _videoModeValues)
          if (draft.videoModes.contains(mode)) ...[
            const SizedBox(height: 8),
            _capabilityInput(
              draft.videoTemplates[mode]!,
              ValueKey('video-capability-template-$mode-$id'),
              '${l10n.settingsVideoPromptTemplate}: $mode',
            ),
          ],
      ],
    );
  }

  Widget _capabilityInput(
    TextEditingController controller,
    Key key,
    String label,
  ) =>
      TextField(
        key: key,
        controller: controller,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => onChanged(),
      );
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
          tooltip: context.l10n.commonEdit,
          icon: Icons.edit_outlined,
          onPressed: onEdit,
        ),
        _SmallIconButton(
          tooltip: context.l10n.settingsManageModels,
          icon: Icons.view_list_outlined,
          onPressed: onManageModels,
        ),
        _SmallIconButton(
          tooltip: context.l10n.settingsTestConnection,
          icon: Icons.network_check_rounded,
          onPressed: onTest,
        ),
        _SmallIconButton(
          tooltip: context.l10n.commonDelete,
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
      'volcengine' => (context.l10n.providerProtocolVolcengine, context.df.red),
      _ => (context.l10n.providerProtocolOpenAiCompatible, context.df.primary),
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
    _apiKey = TextEditingController();
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
    final l10n = context.l10n;
    return AlertDialog(
      title:
          Text(_editing ? l10n.settingsEditProvider : l10n.settingsAddProvider),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                selected: {_protocol},
                segments: [
                  ButtonSegment(
                    value: 'openai_compatible',
                    label: Text(l10n.providerProtocolOpenAiCompatible),
                  ),
                  ButtonSegment(
                    value: 'volcengine',
                    label: Text(l10n.providerProtocolVolcengine),
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
                  labelText: l10n.settingsProviderName,
                  hintText: _editing
                      ? l10n.settingsKeepEmptyUnchanged
                      : l10n.settingsProviderNameHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrl,
                decoration: InputDecoration(
                  labelText: l10n.settingsProviderColumnBaseUrl,
                  hintText: _editing
                      ? l10n.settingsKeepEmptyUnchanged
                      : 'https://...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: l10n.settingsKeepEmptyUnchanged,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
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
          child: Text(l10n.commonSave),
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

  Future<void> _fetchCandidates() async {
    final l10n = context.l10n;
    List<String> ids;
    try {
      ids = await ref
          .read(engineProvider)
          .fetchProviderModelCandidates(widget.provider.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    final known = {for (final d in _drafts) d.modelId.text.trim()};
    final candidates = [
      for (final id in ids)
        if (!known.contains(id)) id,
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.presetFetchEmpty)));
      return;
    }
    final picked = await showModalBottomSheet<List<(String, String)>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CandidateSheet(
        candidates: candidates,
        knownKinds: presetModelKinds(widget.provider.id),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final (id, kind) in picked) {
        _drafts.add(_ModelDraft(
          id: '',
          modelId: TextEditingController(text: id),
          label: TextEditingController(text: id),
          kind: kind,
          capabilities: <String, dynamic>{},
          enabled: false, // spec：候选默认禁用，用户手动启用
        ));
      }
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    for (final draft in _drafts) {
      if (draft.modelId.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsModelIdRequired)),
        );
        return;
      }
      final capabilityError = draft.videoCapabilityError;
      if (capabilityError != null) {
        final message = switch (capabilityError) {
          _VideoCapabilityError.modeRequired =>
            l10n.settingsVideoCapabilityModeRequired,
          _VideoCapabilityError.negativeReference =>
            l10n.settingsVideoReferenceNegative,
          _VideoCapabilityError.listRequired =>
            l10n.settingsVideoCapabilityListRequired,
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
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
          'capabilities': draft.serializedCapabilities(),
          'enabled': draft.enabled,
        }
    ];

    await runAction(context, ref, () async {
      await ref
          .read(engineProvider)
          .saveProviderModels(widget.provider.id, payload);
    }, successMessage: l10n.settingsModelsSaved);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsModelManagementTitle(widget.provider.name)),
        actions: [
          if (wide) ...[
            TextButton.icon(
              key: const Key('model-editor-add'),
              onPressed: _addModel,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.settingsAddModel),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: const Key('model-editor-fetch-models'),
              onPressed: _fetchCandidates,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(l10n.presetFetchModels),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('model-editor-save'),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(l10n.settingsSaveModels),
            ),
          ] else ...[
            IconButton(
              key: const Key('model-editor-add'),
              onPressed: _addModel,
              icon: const Icon(Icons.add_rounded),
              tooltip: l10n.settingsAddModel,
            ),
            IconButton(
              key: const Key('model-editor-fetch-models'),
              onPressed: _fetchCandidates,
              icon: const Icon(Icons.cloud_download_outlined),
              tooltip: l10n.presetFetchModels,
            ),
            IconButton(
              key: const Key('model-editor-save'),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: l10n.settingsSaveModels,
            ),
          ],
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
                title: l10n.settingsModelsEmptyTitle,
                subtitle: l10n.settingsModelsEmptySubtitle,
                action: FilledButton.icon(
                  onPressed: _addModel,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.settingsAddModel),
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
  final Set<String> videoModes;
  final TextEditingController videoImageReferences;
  final TextEditingController videoReferences;
  final TextEditingController audioReferences;
  final TextEditingController videoDurations;
  final TextEditingController videoResolutions;
  final TextEditingController videoRatios;
  final Map<String, TextEditingController> videoTemplates;
  String videoAudio;
  String kind;
  bool enabled;

  _ModelDraft({
    required this.id,
    required this.modelId,
    required this.label,
    required this.kind,
    required this.capabilities,
    required this.enabled,
  })  : videoModes = _videoModes(capabilities),
        videoImageReferences = TextEditingController(
            text: '${_videoReferences(capabilities, 'image')}'),
        videoReferences = TextEditingController(
            text: '${_videoReferences(capabilities, 'video')}'),
        audioReferences = TextEditingController(
            text: '${_videoReferences(capabilities, 'audio')}'),
        videoDurations = TextEditingController(
            text: _videoList(capabilities, 'durations').join(', ')),
        videoResolutions = TextEditingController(
            text: _videoList(capabilities, 'resolutions').join(', ')),
        videoRatios = TextEditingController(
            text: _videoList(capabilities, 'ratios').join(', ')),
        videoTemplates = {
          for (final mode in _videoModeValues)
            mode:
                TextEditingController(text: _videoTemplate(capabilities, mode)),
        },
        videoAudio = _videoAudio(capabilities);

  factory _ModelDraft.fromModel(ProviderModelInfo model) => _ModelDraft(
        id: model.id,
        modelId: TextEditingController(text: model.modelId),
        label: TextEditingController(text: model.label),
        kind: model.kind,
        capabilities: Map<String, dynamic>.from(model.capabilities),
        enabled: model.enabled,
      );

  factory _ModelDraft.empty() => _ModelDraft(
        id: '',
        modelId: TextEditingController(),
        label: TextEditingController(),
        kind: 'text',
        capabilities: <String, dynamic>{},
        enabled: true,
      );

  void dispose() {
    modelId.dispose();
    label.dispose();
    videoImageReferences.dispose();
    videoReferences.dispose();
    audioReferences.dispose();
    videoDurations.dispose();
    videoResolutions.dispose();
    videoRatios.dispose();
    for (final controller in videoTemplates.values) {
      controller.dispose();
    }
  }

  _VideoCapabilityError? get videoCapabilityError {
    if (kind != 'video') return null;
    if (videoModes.isEmpty) return _VideoCapabilityError.modeRequired;
    if ([
      videoImageReferences.text,
      videoReferences.text,
      audioReferences.text,
    ].any(_isInvalidReferenceLimit)) {
      return _VideoCapabilityError.negativeReference;
    }
    if (!_hasPositiveIntegers(videoDurations.text) ||
        _uniqueStrings(videoResolutions.text).isEmpty ||
        _uniqueStrings(videoRatios.text).isEmpty) {
      return _VideoCapabilityError.listRequired;
    }
    return null;
  }

  Map<String, dynamic> serializedCapabilities() {
    if (kind != 'video') return capabilities;
    final modes = [
      for (final mode in _videoModeValues)
        if (videoModes.contains(mode)) mode,
    ];
    final limits = {
      'image': _nonNegative(videoImageReferences.text),
      'video': _nonNegative(videoReferences.text),
      'audio': _nonNegative(audioReferences.text),
    };
    final templates = <String, String>{
      for (final entry in videoTemplates.entries)
        if (modes.contains(entry.key) && entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
    final video = _videoCapability(capabilities)
      ..addAll({
        'modes': modes,
        'references': limits,
        'durations': _positiveInts(videoDurations.text),
        'resolutions': _uniqueStrings(videoResolutions.text),
        'ratios': _uniqueStrings(videoRatios.text),
        'audio': videoAudio,
        'promptTemplates': templates,
      });
    capabilities['video'] = video;
    return capabilities;
  }
}

const _videoModeValues = [
  'text',
  'first_frame',
  'first_last_frame',
  'multi_reference',
];

enum _VideoCapabilityError {
  modeRequired,
  negativeReference,
  listRequired,
}

Map<String, dynamic> _videoCapability(Map<String, dynamic> capabilities) =>
    capabilities['video'] is Map
        ? Map<String, dynamic>.from(capabilities['video'] as Map)
        : const {};

Set<String> _videoModes(Map<String, dynamic> capabilities) => {
      for (final value
          in (_videoCapability(capabilities)['modes'] as List? ?? const []))
        if (_videoModeValues.contains('$value')) '$value',
    };

int _videoReferences(Map<String, dynamic> capabilities, String type) =>
    ((_videoCapability(capabilities)['references'] as Map?)?[type] as num?)
        ?.toInt() ??
    0;

List<String> _videoList(Map<String, dynamic> capabilities, String key) => [
      for (final value
          in (_videoCapability(capabilities)[key] as List? ?? const []))
        '$value',
    ];

String _videoTemplate(Map<String, dynamic> capabilities, String mode) =>
    ((_videoCapability(capabilities)['promptTemplates'] as Map?)?[mode]
        as String?) ??
    '';

String _videoAudio(Map<String, dynamic> capabilities) {
  final value = _videoCapability(capabilities)['audio'];
  return const {'none', 'optional', 'required'}.contains(value)
      ? value as String
      : 'none';
}

int _nonNegative(String value) {
  final parsed = int.tryParse(value.trim()) ?? 0;
  return parsed < 0 ? 0 : parsed;
}

bool _isInvalidReferenceLimit(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return false;
  final parsed = int.tryParse(value);
  return parsed == null || parsed < 0;
}

bool _hasPositiveIntegers(String raw) {
  final values = raw.split(',').map((part) => part.trim()).toList();
  return values.isNotEmpty &&
      values.every((value) {
        final parsed = int.tryParse(value);
        return parsed != null && parsed > 0;
      });
}

List<int> _positiveInts(String raw) {
  final values = <int>[];
  for (final part in raw.split(',')) {
    final value = int.tryParse(part.trim());
    if (value != null && value > 0 && !values.contains(value)) {
      values.add(value);
    }
  }
  return values;
}

List<String> _uniqueStrings(String raw) {
  final values = <String>[];
  for (final part in raw.split(',')) {
    final value = part.trim();
    if (value.isNotEmpty && !values.contains(value)) values.add(value);
  }
  return values;
}

class _CandidateSheet extends StatefulWidget {
  final List<String> candidates;
  final Map<String, String> knownKinds;
  const _CandidateSheet({required this.candidates, required this.knownKinds});

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  late final Map<String, String?> _kinds = {
    for (final id in widget.candidates) id: widget.knownKinds[id],
  };
  final Set<String> _checked = {};
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String kindLabel(String k) => switch (k) {
          'image' => l10n.presetKindImage,
          'video' => l10n.presetKindVideo,
          'tts' => l10n.presetKindTts,
          _ => l10n.presetKindText,
        };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final id in widget.candidates)
                    Row(
                      key: Key('candidate-row-$id'),
                      children: [
                        Checkbox(
                          key: Key('candidate-check-$id'),
                          value: _checked.contains(id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _checked.add(id);
                            } else {
                              _checked.remove(id);
                            }
                          }),
                        ),
                        Expanded(
                          child: Text(id,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownButton<String>(
                          key: Key('candidate-kind-$id'),
                          value: _kinds[id],
                          hint: Text(l10n.presetUncategorized),
                          items: [
                            for (final k in const [
                              'text',
                              'image',
                              'video',
                              'tts'
                            ])
                              DropdownMenuItem(
                                  value: k, child: Text(kindLabel(k))),
                          ],
                          onChanged: (v) => setState(() => _kinds[id] = v),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final missing =
                    _checked.where((id) => _kinds[id] == null).toList();
                if (missing.isNotEmpty) {
                  setState(() => _error = l10n.presetKindRequired);
                  return;
                }
                Navigator.of(context).pop([
                  for (final id in _checked) (id, _kinds[id]!),
                ]);
              },
              child: Text(l10n.presetAddCandidates),
            ),
          ],
        ),
      ),
    );
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
    final l10n = context.l10n;
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
            child: Row(
              children: [
                const _HeaderFlexCell(flex: 18, label: 'Model ID'),
                _HeaderFlexCell(flex: 18, label: 'Label'),
                _HeaderCell(width: 132, label: l10n.commonType),
                _HeaderCell(width: 92, label: l10n.commonEnabled),
                const _HeaderCell(width: 64, label: ''),
              ],
            ),
          ),
          for (final draft in drafts)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.df.stroke)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _FormFlexCell(
                        flex: 18,
                        child: TextField(
                          controller: draft.modelId,
                          decoration:
                              const InputDecoration(labelText: 'Model ID'),
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
                          decoration:
                              InputDecoration(labelText: l10n.commonType),
                          items: [
                            for (final kind in _modelKinds)
                              DropdownMenuItem(
                                value: kind.value,
                                child: Text(kind.label(context.l10n)),
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
                          tooltip: l10n.settingsDeleteModel,
                          icon: Icon(Icons.delete_outline_rounded,
                              color: context.df.red),
                          onPressed: () => onRemove(draft),
                        ),
                      ),
                    ],
                  ),
                  if (draft.kind == 'video') ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Material(
                        color: context.df.surface,
                        child: _VideoCapabilityEditor(
                          draft: draft,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                  ],
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
    final l10n = context.l10n;
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
                  decoration: InputDecoration(labelText: l10n.commonType),
                  items: [
                    for (final kind in _modelKinds)
                      DropdownMenuItem(
                        value: kind.value,
                        child: Text(kind.label(l10n)),
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
                tooltip: l10n.settingsDeleteModel,
                icon: Icon(Icons.delete_outline_rounded, color: context.df.red),
                onPressed: onRemove,
              ),
            ],
          ),
          if (draft.kind == 'video') ...[
            const SizedBox(height: 10),
            Material(
              color: context.df.surface,
              child: _VideoCapabilityEditor(draft: draft, onChanged: onChanged),
            ),
          ],
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
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stage.title(l10n),
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
          stage.description(l10n),
          style: TextStyle(color: context.df.textLo, fontSize: 12),
        ),
        if (missing) ...[
          const SizedBox(height: 6),
          Text(
            l10n.stageBindingMissing,
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
    final l10n = context.l10n;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.settingsBindingModel,
        errorText: missing ? l10n.settingsSelectEnabledModel : null,
      ),
      hint: Text(l10n.settingsSelectModel),
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
          orElse: () => const _KindMeta('text'),
        )
        .label(context.l10n);
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
    final l10n = context.l10n;
    final content = (prompt?['content'] ?? '').toString();
    final updatedAt = (prompt?['updatedAt'] ?? '').toString();
    final isOverridden = prompt?['isOverridden'] == true;
    final preview = content.trim().replaceAll(r'\n', ' ').replaceAll('\n', ' ');
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            meta.title(l10n),
                            style: TextStyle(
                              color: context.df.textHi,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isOverridden) ...[
                          const SizedBox(width: 8),
                          _PromptOverrideBadge(label: l10n.promptOverridden),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta.description(l10n),
                      style: TextStyle(color: context.df.textLo, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview.isEmpty ? l10n.promptUnset : preview,
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
                      '${l10n.promptCharacterCount(content.length)}${updatedAt.isEmpty ? '' : ' · $updatedAt'}',
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

class _SubsectionTitle extends StatelessWidget {
  final String label;

  const _SubsectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.df.textHi,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ModelPromptRow extends StatelessWidget {
  final Map<String, dynamic> prompt;
  final VoidCallback onOpen;

  const _ModelPromptRow({
    required this.prompt,
    required this.onOpen,
  });

  String get _title {
    final provider = (prompt['providerName'] ?? '').toString();
    final model = (prompt['modelLabel'] ?? prompt['model'] ?? '').toString();
    final key = ((prompt['fileName'] ?? '').toString().isNotEmpty
            ? prompt['fileName']
            : prompt['path'])
        .toString();
    return [provider, model, key].where((v) => v.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = (prompt['prompt'] ?? '').toString();
    final preview = content.trim().replaceAll(r'\n', ' ').replaceAll('\n', ' ');
    final path = (prompt['path'] ?? '').toString();
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
                      _title,
                      style: TextStyle(
                        color: context.df.textHi,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (path.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        path,
                        style:
                            TextStyle(color: context.df.textLo, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      preview.isEmpty ? l10n.promptUnset : preview,
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
                      l10n.promptCharacterCount(content.length),
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

class _PromptOverrideBadge extends StatelessWidget {
  final String label;

  const _PromptOverrideBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.df.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.df.primary.withValues(alpha: 0.35)),
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

class _ModelPromptEditorPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> prompt;

  const _ModelPromptEditorPage({required this.prompt});

  @override
  ConsumerState<_ModelPromptEditorPage> createState() =>
      _ModelPromptEditorPageState();
}

class _ModelPromptEditorPageState
    extends ConsumerState<_ModelPromptEditorPage> {
  late final TextEditingController _controller;

  String get _title {
    final provider = (widget.prompt['providerName'] ?? '').toString();
    final model = (widget.prompt['modelLabel'] ?? widget.prompt['model'] ?? '')
        .toString();
    final key = ((widget.prompt['fileName'] ?? '').toString().isNotEmpty
            ? widget.prompt['fileName']
            : widget.prompt['path'])
        .toString();
    return [provider, model, key].where((v) => v.isNotEmpty).join(' · ');
  }

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: (widget.prompt['prompt'] ?? '').toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    await runAction(context, ref, () async {
      await ref
          .read(engineProvider)
          .updateModelPrompt(widget.prompt['id'] as int, _controller.text);
    }, successMessage: l10n.promptSaved);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptEditTitle(_title)),
        actions: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(l10n.commonSave),
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
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  labelText: l10n.settingsPromptContent,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Text(
                  l10n.promptCharacterCount(_controller.text.length),
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
    final l10n = context.l10n;
    await runAction(context, ref, () async {
      await ref
          .read(engineProvider)
          .updatePrompt(widget.meta.key, _controller.text);
    }, successMessage: l10n.promptSaved);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    final l10n = context.l10n;
    final title = widget.meta.title(l10n);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.promptRestoreDefaultTitle),
        content: Text(l10n.promptRestoreDefaultMessage(title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.promptRestoreDefaultConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).resetPrompt(widget.meta.key);
    }, successMessage: l10n.promptRestored);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptEditTitle(widget.meta.title(l10n))),
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: Text(l10n.promptRestoreDefault),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(l10n.commonSave),
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
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  labelText: l10n.settingsPromptContent,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Text(
                  l10n.promptCharacterCount(_controller.text.length),
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
              value.isEmpty ? context.l10n.commonUnset : value,
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
