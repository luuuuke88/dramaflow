import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dramaflow/l10n/app_localizations.dart';

import '../api/models.dart';
import '../engine/provider_presets.dart';
import '../engine/providers/resolve.dart';
import '../engine/util.dart';
import '../state/providers.dart';
import '../util/l10n_ext.dart';
import '../widgets/common.dart';
import '../widgets/df_adaptive_dialog.dart';

/// 预设预填表单。返回 true = 创建或编辑成功。
Future<bool> showProviderPresetForm(
  BuildContext context,
  WidgetRef ref, {
  required String presetId,
  ProviderInfo? existingProvider,
}) async {
  final preset = providerPresetById(presetId);
  if (preset == null ||
      (existingProvider != null && existingProvider.id != preset.id)) {
    return false;
  }
  final initialInputs = existingProvider == null
      ? const <String, String>{}
      : await ref.read(engineProvider).providerPresetInputs(preset.id);
  if (!context.mounted) return false;
  final saved = await showDFAdaptiveDialog<bool>(
    context,
    title: preset.name,
    desktopWidthFactor: .5,
    builder: (context) => _PresetFormBody(
      preset: preset,
      existingProvider: existingProvider,
      initialInputs: initialInputs,
    ),
  );
  return saved == true;
}

class _PresetFormBody extends ConsumerStatefulWidget {
  final ProviderPreset preset;
  final ProviderInfo? existingProvider;
  final Map<String, String> initialInputs;

  const _PresetFormBody({
    required this.preset,
    required this.existingProvider,
    required this.initialInputs,
  });

  @override
  ConsumerState<_PresetFormBody> createState() => _PresetFormBodyState();
}

class _PresetFormBodyState extends ConsumerState<_PresetFormBody> {
  late final TextEditingController _name = TextEditingController(
      text: widget.existingProvider?.name ?? widget.preset.name);
  late final TextEditingController _baseUrl;
  late final Map<String, TextEditingController> _inputValues;
  final TextEditingController _apiKey = TextEditingController();
  late final Set<String> _selected = {
    for (final m in widget.preset.models) m.modelId,
  };
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  bool get _usesIma2Inputs => widget.preset.protocol == 'ima2';
  bool get _isEditing => widget.existingProvider != null;

  @override
  void initState() {
    super.initState();
    final isMobile = ref.read(engineProvider).config.isMobile;
    _inputValues = {
      for (final entry in widget.preset.inputDefaults.entries)
        entry.key: TextEditingController(text: () {
          final stored = widget.initialInputs[entry.key] ?? entry.value;
          return isMobile && isLoopbackBaseUrl(stored) ? '' : stored;
        }()),
    };
    _baseUrl = TextEditingController(
      text: _usesIma2Inputs
          ? (_inputValues['chatBaseUrl']?.text ?? '')
          : (widget.existingProvider?.baseUrl ?? widget.preset.baseUrl),
    );
  }

  String get _effectiveBaseUrl => _usesIma2Inputs
      ? (_inputValues['chatBaseUrl']?.text ?? '')
      : _baseUrl.text;

  bool get _inputsComplete => _inputValues.values
      .every((controller) => controller.text.trim().isNotEmpty);

  bool get _canSave =>
      !_saving &&
      (_isEditing || _selected.isNotEmpty) &&
      _inputsComplete &&
      (isLoopbackBaseUrl(_effectiveBaseUrl) ||
          widget.existingProvider?.hasCredential == true ||
          _apiKey.text.trim().isNotEmpty);

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    for (final controller in _inputValues.values) {
      controller.dispose();
    }
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final inputOverrides = {
        for (final entry in _inputValues.entries) entry.key: entry.value.text,
      };
      if (_isEditing) {
        await ref.read(engineProvider).updateProvider(
              widget.existingProvider!.id,
              name: _name.text,
              baseUrl: _effectiveBaseUrl,
              apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text,
              inputOverrides: inputOverrides,
            );
      } else {
        await ref.read(engineProvider).createProviderFromPreset(
              presetId: widget.preset.id,
              apiKey: _apiKey.text,
              selectedModelIds: _selected.toList(),
              name: _name.text,
              baseUrl: _effectiveBaseUrl,
              inputOverrides: inputOverrides,
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on EngineException catch (e) {
      // 与 settings_screen.dart 其它供应商增删改路径同源的本地化映射
      // （common.dart 的 engineErrorText，runAction 内部也用它），不把
      // errKey/参数 Map 原样 toString() 展示给用户。errProviderExists 是最
      // 现实的失败场景（重复创建竞争），路由到 Task 4 专门加的文案。
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _saving = false;
        _error = e.errKey == errProviderExists
            ? l10n.presetProviderExists
            : engineErrorText(context, e);
      });
    } catch (e) {
      // 非 EngineException 的意外失败：Task 2/3 的引擎方法已把用户能真实
      // 触发的失败（重复创建/缺模型/网络/凭证）包装成 EngineException 走上面
      // 分支；这里退到已有的通用“操作失败”本地化文案，绝不裸露 '$e'。
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.projectMsgOperationFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('preset-form-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.settingsProviderName),
          ),
          const SizedBox(height: 12),
          if (!_usesIma2Inputs) ...[
            TextField(
              key: const Key('preset-form-baseurl'),
              controller: _baseUrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: l10n.settingsProviderColumnBaseUrl),
            ),
            const SizedBox(height: 12),
          ],
          if (_usesIma2Inputs)
            for (final entry in _inputValues.entries) ...[
              TextField(
                key: Key('preset-input-${entry.key}'),
                controller: entry.value,
                keyboardType: entry.key.endsWith('BaseUrl')
                    ? TextInputType.url
                    : TextInputType.text,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _inputLabel(l10n, entry.key),
                ),
              ),
              const SizedBox(height: 12),
            ],
          TextField(
            key: const Key('preset-form-apikey'),
            controller: _apiKey,
            autofocus: true,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'API Key',
              suffixIcon: IconButton(
                key: const Key('preset-form-apikey-toggle'),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l10n.presetOpenPlatform),
              onPressed: () => launchUrl(Uri.parse(widget.preset.keyUrl)),
            ),
          ),
          if (!_isEditing) ...[
            const Divider(height: 24),
            for (final m in widget.preset.models)
              CheckboxListTile(
                key: Key('preset-model-${m.modelId}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(m.modelId),
                title: Text(m.modelId,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(m.modelId);
                  } else {
                    _selected.remove(m.modelId);
                  }
                }),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('preset-form-save'),
            onPressed: _canSave ? _save : null,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }

  String _inputLabel(AppLocalizations l10n, String key) => switch (key) {
        'chatBaseUrl' => l10n.providerInputChatBaseUrl,
        'imageBaseUrl' => l10n.providerInputImageBaseUrl,
        'imageQuality' => l10n.providerInputImageQuality,
        'imageSize' => l10n.providerInputImageSize,
        'imageTimeoutMs' => l10n.providerInputImageTimeoutMs,
        _ => key,
      };
}
