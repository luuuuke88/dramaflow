import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/provider_presets.dart';
import '../engine/providers/resolve.dart';
import '../engine/util.dart';
import '../state/providers.dart';
import '../util/l10n_ext.dart';
import '../widgets/common.dart';
import '../widgets/df_adaptive_dialog.dart';

/// 预设预填表单（spec §5 第 2 条）。返回 true = 创建成功。
Future<bool> showProviderPresetForm(
  BuildContext context,
  WidgetRef ref, {
  required String presetId,
}) async {
  final preset = providerPresetById(presetId);
  if (preset == null) return false;
  final created = await showDFAdaptiveDialog<bool>(
    context,
    title: preset.name,
    desktopWidthFactor: .5,
    builder: (context) => _PresetFormBody(preset: preset),
  );
  return created == true;
}

class _PresetFormBody extends ConsumerStatefulWidget {
  final ProviderPreset preset;
  const _PresetFormBody({required this.preset});

  @override
  ConsumerState<_PresetFormBody> createState() => _PresetFormBodyState();
}

class _PresetFormBodyState extends ConsumerState<_PresetFormBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.preset.name);
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.preset.baseUrl);
  final TextEditingController _apiKey = TextEditingController();
  late final Set<String> _selected = {
    for (final m in widget.preset.models) m.modelId,
  };
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  bool get _canSave =>
      !_saving &&
      _selected.isNotEmpty &&
      (isLoopbackBaseUrl(_baseUrl.text) || _apiKey.text.trim().isNotEmpty);

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(engineProvider).createProviderFromPreset(
            presetId: widget.preset.id,
            apiKey: _apiKey.text,
            selectedModelIds: _selected.toList(),
            name: _name.text,
            baseUrl: _baseUrl.text,
          );
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
          TextField(
            key: const Key('preset-form-baseurl'),
            controller: _baseUrl,
            onChanged: (_) => setState(() {}),
            decoration:
                InputDecoration(labelText: l10n.settingsProviderColumnBaseUrl),
          ),
          const SizedBox(height: 12),
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
          const Divider(height: 24),
          for (final m in widget.preset.models)
            CheckboxListTile(
              key: Key('preset-model-${m.modelId}'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(m.modelId),
              title:
                  Text(m.modelId, maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(m.modelId);
                } else {
                  _selected.remove(m.modelId);
                }
              }),
            ),
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
}
