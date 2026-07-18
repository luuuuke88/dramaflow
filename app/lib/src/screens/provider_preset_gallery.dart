import 'package:flutter/material.dart';

import '../engine/provider_presets.dart';
import '../theme/theme.dart';
import '../util/l10n_ext.dart';
import '../widgets/df_adaptive_dialog.dart';

/// 预设画廊（spec §5 第 1 条）：返回选中 presetId；'custom' 走自定义；null 取消。
Future<String?> showProviderPresetGallery(
  BuildContext context, {
  required Set<String> existingProviderIds,
}) {
  final l10n = context.l10n;
  return showDFAdaptiveDialog<String>(
    context,
    title: l10n.presetGalleryTitle,
    desktopWidthFactor: .72,
    builder: (context) => _PresetGalleryBody(existing: existingProviderIds),
  );
}

class _PresetGalleryBody extends StatelessWidget {
  final Set<String> existing;
  const _PresetGalleryBody({required this.existing});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600 ? 2 : (width < 1100 ? 3 : 4);
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: columns,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        for (final p in kProviderPresets)
          _PresetCard(preset: p, added: existing.contains(p.id)),
        const _CustomCard(),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final ProviderPreset preset;
  final bool added;
  const _PresetCard({required this.preset, required this.added});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = context.l10n;
    final kinds = {for (final m in preset.models) m.kind};
    String kindLabel(String k) => switch (k) {
          'image' => l10n.presetKindImage,
          'video' => l10n.presetKindVideo,
          'tts' => l10n.presetKindTts,
          _ => l10n.presetKindText,
        };
    final badges = <String>[
      if (added)
        l10n.presetAdded
      else ...[
        if (!preset.acceptanceVerified) l10n.presetUnverified,
        if (preset.compatMode) l10n.presetCompatMode,
      ],
    ];
    return InkWell(
      key: Key('preset-card-${preset.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop(preset.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(preset.name.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 13)),
                ),
                const Spacer(),
                Flexible(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [for (final b in badges) _Badge(text: b)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final k in kinds) _Badge(text: kindLabel(k)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _CustomCard extends StatelessWidget {
  const _CustomCard();

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = context.l10n;
    return InkWell(
      key: const Key('preset-card-custom'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop('custom'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: df.textSecondary),
            const SizedBox(height: 6),
            Text(l10n.presetGalleryCustom,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(l10n.presetGalleryCustomDesc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: df.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: df.stroke),
        borderRadius: BorderRadius.circular(4),
      ),
      child:
          Text(text, style: TextStyle(fontSize: 10, color: df.textSecondary)),
    );
  }
}
