// 模型选择器（对应 ToonFlow modelSelect 组件）：列出所有启用供应商的对应
// kind 启用模型，值 = 'providerId:modelId'。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/df_select.dart';

class ModelOption {
  final String value; // providerId:modelId
  final String label; // 供应商 · 模型
  final Map<String, dynamic> capabilities;
  const ModelOption(this.value, this.label, this.capabilities);
}

final modelOptionsProvider = FutureProvider.autoDispose
    .family<List<ModelOption>, String>((ref, kind) async {
  final engine = ref.watch(engineProvider);
  final providers = await engine.listProviders();
  final options = <ModelOption>[];
  for (final ProviderInfo provider in providers) {
    if (!provider.enabled) continue;
    for (final ProviderModelInfo model
        in await engine.listProviderModels(provider.id)) {
      if (!model.enabled || model.kind != kind) continue;
      options.add(ModelOption(
        '${provider.id}:${model.modelId}',
        '${provider.name} · ${model.label.isEmpty ? model.modelId : model.label}',
        model.capabilities,
      ));
    }
  }
  return options;
});

class ModelSelect extends ConsumerWidget {
  final String kind; // image / video / text / tts
  final String? value;
  final String hint;
  final ValueChanged<ModelOption?> onChanged;

  const ModelSelect({
    super.key,
    required this.kind,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    final options = ref.watch(modelOptionsProvider(kind));
    return options.when(
      loading: () => const SizedBox(
          height: 40, child: Center(child: LinearProgressIndicator())),
      error: (e, _) => Text('$e',
          style: TextStyle(color: df.danger, fontSize: 12)),
      data: (items) {
        final valid = items.any((o) => o.value == value) ? value : null;
        return DFSelect<String>(
          value: valid,
          hint: hint,
          items: [
            for (final o in items)
              DFSelectItem(value: o.value, label: o.label),
          ],
          onChanged: (v) => onChanged(
              v == null ? null : items.firstWhere((o) => o.value == v)),
        );
      },
    );
  }
}
