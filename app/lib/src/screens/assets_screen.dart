import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 素材库：角色 / 场景 两个分区的响应式网格。
class AssetsScreen extends ConsumerWidget {
  final String projectId;

  const AssetsScreen({super.key, required this.projectId});

  Future<void> _extract(BuildContext context, WidgetRef ref) =>
      runAction(context, ref, () async {
        await ref.read(engineProvider).extractAssets(projectId);
      }, successMessage: '素材提取任务已排队');

  Future<void> _generateAll(BuildContext context, WidgetRef ref) async {
    int? queued;
    await runAction(context, ref, () async {
      final ids = await ref.read(engineProvider).generateAllAssetImages(projectId);
      queued = ids.length;
    });
    if (queued != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(queued == 0
            ? '没有需要生成的素材图片（已完成或进行中的会被跳过）'
            : '已排队 $queued 个图片生成任务'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(assetsProvider(projectId));
    final compact = MediaQuery.sizeOf(context).width < 620;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回项目',
          onPressed: () => context.go('/projects/$projectId'),
        ),
        title: const Text('素材库'),
        actions: [
          if (compact) ...[
            IconButton(
              tooltip: '提取素材',
              icon: const Icon(Icons.auto_fix_high_rounded),
              onPressed: () => _extract(context, ref),
            ),
            IconButton(
              tooltip: '批量生成图片',
              icon: const Icon(Icons.burst_mode_rounded),
              color: DF.amber,
              onPressed: () => _generateAll(context, ref),
            ),
          ] else ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('提取素材'),
              onPressed: () => _extract(context, ref),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              icon: const Icon(Icons.burst_mode_rounded, size: 18),
              label: const Text('批量生成图片'),
              onPressed: () => _generateAll(context, ref),
            ),
          ],
          const SizedBox(width: 16),
        ],
      ),
      body: PageContainer(
        child: AsyncView(
          value: assetsAsync,
          onRetry: () => ref.invalidate(assetsProvider(projectId)),
          builder: (assets) {
            if (assets.isEmpty) {
              return const EmptyHint(
                icon: Icons.palette_outlined,
                title: '还没有素材',
                subtitle: '先在流水线页提取素材，或等待剧本生成完成',
              );
            }
            final characters =
                assets.where((a) => a.kind == 'character').toList();
            final scenes = assets.where((a) => a.kind != 'character').toList();
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                if (characters.isNotEmpty)
                  ..._section(context, '角色', Icons.person_outline_rounded,
                      characters),
                if (scenes.isNotEmpty)
                  ..._section(
                      context, '场景', Icons.landscape_outlined, scenes),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _section(
      BuildContext context, String title, IconData icon, List<Asset> items) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: DF.amber),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: DF.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: DF.stroke),
                ),
                child: Text('${items.length}',
                    style: const TextStyle(fontSize: 12, color: DF.textMid)),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 28),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            childAspectRatio: 0.78,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) =>
                _AssetCard(asset: items[i], projectId: projectId),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

/// 单个素材卡片：方图 + 状态角标 + 名称/描述 + 操作行。
class _AssetCard extends ConsumerWidget {
  final Asset asset;
  final String projectId;

  const _AssetCard({required this.asset, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final busy = asset.status == 'queued' || asset.status == 'running';
    final done = asset.status == 'done';
    final failed = asset.status == 'failed';
    final error = asset.error;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAssetDetail(context, asset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Stack(
                  children: [
                    Positioned.fill(child: MediaImage(asset.imageUrl)),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: StatusChip(asset.status,
                          dense: true, errorTooltip: error),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.name,
                      style: theme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (asset.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(asset.description,
                        style: theme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (failed && error != null && error.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Tooltip(
                      message: error,
                      child: Text(error,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: DF.red, height: 1.35)),
                    ),
                  ],
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniButton(
                          icon: done || failed
                              ? Icons.refresh_rounded
                              : Icons.image_rounded,
                          label: failed ? '重试' : (done ? '重新生成' : '生成图片'),
                          color: DF.amber,
                          onPressed: busy
                              ? null
                              : () => runAction(context, ref, () async {
                                    await ref
                                        .read(engineProvider)
                                        .generateAssetImage(asset.id);
                                  }, successMessage: '图片生成任务已排队'),
                        ),
                        const SizedBox(width: 4),
                        _MiniButton(
                          icon: Icons.edit_outlined,
                          label: '编辑',
                          color: DF.textMid,
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => _AssetEditDialog(
                                asset: asset, projectId: projectId),
                          ),
                        ),
                      ],
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
}

/// 紧凑型文字按钮（卡片脚部用）。
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _MiniButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// 详情弹窗：大图 + 描述 / 图片提示词（可选中复制）。
void _showAssetDetail(BuildContext context, Asset asset) {
  final error = asset.error;
  showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context).textTheme;
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(asset.name,
                          style: theme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 12),
                    StatusChip(asset.status, errorTooltip: error),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 480, maxHeight: 480),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: MediaImage(asset.imageUrl, radius: 12),
                    ),
                  ),
                ),
                if (asset.status == 'failed' &&
                    error != null &&
                    error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(error,
                      style: const TextStyle(
                          fontSize: 13, color: DF.red, height: 1.4)),
                ],
                const SizedBox(height: 20),
                const Text('描述',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DF.textLo)),
                const SizedBox(height: 6),
                SelectableText(
                    asset.description.isEmpty ? '—' : asset.description,
                    style: theme.bodyMedium),
                const SizedBox(height: 16),
                const Text('图片提示词',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DF.textLo)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DF.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DF.stroke),
                  ),
                  child: SelectableText(
                      asset.imagePrompt.isEmpty ? '—' : asset.imagePrompt,
                      style: theme.bodySmall?.copyWith(height: 1.6)),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 编辑弹窗：名称 / 描述 / 图片提示词。
class _AssetEditDialog extends ConsumerStatefulWidget {
  final Asset asset;
  final String projectId;

  const _AssetEditDialog({required this.asset, required this.projectId});

  @override
  ConsumerState<_AssetEditDialog> createState() => _AssetEditDialogState();
}

class _AssetEditDialogState extends ConsumerState<_AssetEditDialog> {
  late final _name = TextEditingController(text: widget.asset.name);
  late final _desc = TextEditingController(text: widget.asset.description);
  late final _prompt = TextEditingController(text: widget.asset.imagePrompt);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    var ok = false;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateAsset(
            widget.asset.id,
            name: _name.text.trim(),
            description: _desc.text.trim(),
            imagePrompt: _prompt.text.trim(),
          );
      ok = true;
    }, successMessage: '素材已保存');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ref.invalidate(assetsProvider(widget.projectId));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑素材'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _desc,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: '描述', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _prompt,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                    labelText: '图片提示词', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
