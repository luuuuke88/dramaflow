// 模型选择器（对应 ToonFlow modelSelect 组件）：列出所有启用供应商的对应
// kind 启用模型，值 = 'providerId:modelId'。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../engine/engine.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/l10n_ext.dart';

class ModelOption {
  final String value; // providerId:modelId
  final String providerId;
  final String providerName;
  /// 供应商加模型名；保留既有调用方的展示契约。
  final String label;
  final String kind;
  final Map<String, dynamic> capabilities;
  const ModelOption({
    required this.value,
    required this.providerId,
    required this.providerName,
    required this.label,
    required this.kind,
    required this.capabilities,
  });
}

Future<List<ModelOption>> loadModelOptions(Engine engine, String kind) async {
  final providers = await engine.listProviders();
  final options = <ModelOption>[];
  for (final ProviderInfo provider in providers) {
    if (!provider.enabled) continue;
    for (final ProviderModelInfo model
        in await engine.listProviderModels(provider.id)) {
      if (!model.enabled || model.kind != kind) continue;
      options.add(ModelOption(
        value: '${provider.id}:${model.modelId}',
        providerId: provider.id,
        providerName: provider.name,
        label:
            '${provider.name} · ${model.label.isEmpty ? model.modelId : model.label}',
        kind: model.kind,
        capabilities: model.capabilities,
      ));
    }
  }
  return options;
}

final modelOptionsProvider = FutureProvider.autoDispose
    .family<List<ModelOption>, String>(
        (ref, kind) => loadModelOptions(ref.watch(engineProvider), kind));

class ModelSelect extends ConsumerStatefulWidget {
  final String kind; // image / video / text / tts
  final String? value;
  final String hint;
  final ValueChanged<ModelOption?> onChanged;
  final VoidCallback? onConfigure;

  const ModelSelect({
    super.key,
    required this.kind,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.onConfigure,
  });

  @override
  ConsumerState<ModelSelect> createState() => _ModelSelectState();
}

class _ModelSelectState extends ConsumerState<ModelSelect> {
  Future<void> _openMenu() async {
    final context = this.context;
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final latest =
        await loadModelOptions(ref.read(engineProvider), widget.kind);
    if (!context.mounted) return;
    ref.invalidate(modelOptionsProvider(widget.kind));
    if (latest.isEmpty) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final selected = await showMenu<ModelOption>(
      context: context,
      position: RelativeRect.fromRect(
        origin & box.size,
        Offset.zero & overlayBox.size,
      ),
      items: _modelMenuItems(latest),
    );
    if (selected != null && context.mounted) widget.onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final options = ref.watch(modelOptionsProvider(widget.kind));
    return options.when(
      loading: () => const SizedBox(
          height: 40, child: Center(child: LinearProgressIndicator())),
      error: (e, _) =>
          Text('$e', style: TextStyle(color: df.danger, fontSize: 12)),
      data: (items) {
        if (items.isEmpty && widget.onConfigure != null) {
          return InputDecorator(
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  widget.hint,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: df.textTertiary, fontSize: 13),
                ),
              ),
              TextButton.icon(
                key: Key('model-select-configure-${widget.kind}'),
                onPressed: widget.onConfigure,
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: Text(context.l10n.modelSelectGoSettings),
              ),
            ]),
          );
        }
        final selected = items.cast<ModelOption?>().firstWhere(
            (option) => option?.value == widget.value,
            orElse: () => null);
        return Semantics(
          button: true,
          child: InkWell(
            key: Key('model-select-field-${widget.kind}'),
            onTap: _openMenu,
            child: InputDecorator(
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              child: selected == null
                  ? Text(widget.hint,
                      style: TextStyle(color: df.textTertiary, fontSize: 13))
                  : _ModelOptionRow(option: selected),
            ),
          ),
        );
      },
    );
  }
}

List<PopupMenuEntry<ModelOption>> _modelMenuItems(List<ModelOption> items) {
  final groups = <String, List<ModelOption>>{};
  for (final option in items) {
    groups.putIfAbsent(option.providerId, () => []).add(option);
  }
  return [
    for (final group in groups.entries) ...[
      PopupMenuItem<ModelOption>(
        enabled: false,
        child: _ProviderHeader(
          key: Key('model-select-provider-${group.key}'),
          providerName: group.value.first.providerName,
        ),
      ),
      for (final option in group.value)
        PopupMenuItem(
          value: option,
          child: _ModelOptionRow(option: option),
        ),
    ],
  ];
}

class _ProviderHeader extends StatelessWidget {
  final String providerName;

  const _ProviderHeader({super.key, required this.providerName});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        providerName,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: df.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ModelOptionRow extends StatelessWidget {
  final ModelOption option;

  const _ModelOptionRow({required this.option});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final name = option.providerName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: _providerColor(option.providerId),
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(option.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Text(
          _modelKindLabel(context, option.kind),
          style: TextStyle(color: df.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

String _modelKindLabel(BuildContext context, String kind) => switch (kind) {
      'text' => context.l10n.modelKindText,
      'image' => context.l10n.modelKindImage,
      'video' => context.l10n.modelKindVideo,
      'tts' => context.l10n.modelKindTts,
      'embedding' => context.l10n.modelKindEmbedding,
      _ => kind,
    };

Color _providerColor(String id) {
  const colors = [
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFFE65100),
    Color(0xFF6A1B9A),
    Color(0xFF546E7A),
  ];
  var hash = 0;
  for (final code in id.codeUnits) {
    hash = (hash * 31 + code) & 0x7FFFFFFF;
  }
  return colors[hash % colors.length];
}
