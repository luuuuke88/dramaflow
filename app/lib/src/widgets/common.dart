import 'dart:io';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/models.dart';
import '../engine/util.dart';
import '../state/providers.dart';
import '../theme/theme.dart';

/// 状态 → 视觉语义 的唯一映射，全 App 统一。
class StatusChip extends StatelessWidget {
  final String status;
  final String? errorTooltip;
  final bool dense;

  const StatusChip(this.status,
      {super.key, this.errorTooltip, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color, icon) = switch (status) {
      'queued' => (l10n.statusQueued, context.df.blue, Icons.schedule_rounded),
      'pending' =>
        (l10n.statusPending, context.df.blue, Icons.schedule_rounded),
      'running' =>
        (l10n.statusRunning, context.df.primary, Icons.autorenew_rounded),
      'processing' =>
        (l10n.statusRunning, context.df.primary, Icons.autorenew_rounded),
      'done' =>
        (l10n.statusDone, context.df.green, Icons.check_circle_rounded),
      'success' =>
        (l10n.statusDone, context.df.green, Icons.check_circle_rounded),
      'failed' => (l10n.statusFailed, context.df.red, Icons.error_rounded),
      'canceled' => (l10n.statusCanceled, context.df.grey, Icons.block_rounded),
      'draft' => (l10n.statusDraft, context.df.grey, Icons.edit_note_rounded),
      _ => (l10n.statusNotGenerated, context.df.grey, Icons.circle_outlined),
    };
    final chip = Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'running' || status == 'processing')
            SizedBox(
              width: dense ? 10 : 12,
              height: dense ? 10 : 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: dense ? 12 : 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
    if (status == 'failed' &&
        errorTooltip != null &&
        errorTooltip!.isNotEmpty) {
      return Tooltip(
        message: errorTooltip!,
        waitDuration: const Duration(milliseconds: 300),
        child: chip,
      );
    }
    return chip;
  }
}

/// AsyncValue 的统一渲染（加载骨架 / 错误重试 / 数据）。
class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  const AsyncView(
      {super.key, required this.value, required this.builder, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      // 已有数据时后台刷新失败不清屏（任务活跃期数据 Provider 会频繁重取）
      skipError: true,
      data: builder,
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: CircularProgressIndicator(color: context.df.primary),
        ),
      ),
      error: (e, _) => ErrorCard(message: e.toString(), onRetry: onRetry),
    );
  }
}

class ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorCard({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 40, color: context.df.red),
                const SizedBox(height: 12),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.df.textMid, height: 1.5)),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(AppLocalizations.of(context).commonRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.df.card,
                shape: BoxShape.circle,
                border: Border.all(color: context.df.stroke),
              ),
              child: Icon(icon, size: 32, color: context.df.textLo),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.df.textHi)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.df.textLo, height: 1.5)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// 执行生成类动作的统一封装：错误弹 SnackBar，成功后立刻 poke 轮询器。
Future<bool> runAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  // 在 await 之前取全局 notifier：请求期间 widget 可能被卸载（关对话框/切页），
  // 卸载后再用 widget 的 ref 会被 Riverpod 3 直接抛 StateError
  final jobsNotifier = ref.read(activeJobsProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    jobsNotifier.poke();
    if (successMessage != null && messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
            content: Text(successMessage),
            duration: const Duration(seconds: 2)),
      );
    }
    return true;
  } on EngineException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(engineErrorText(context, e),
            style: const TextStyle(color: Colors.white)),
        backgroundColor: context.df.red,
        duration: const Duration(seconds: 4),
      ));
    }
    return false;
  }
}

/// EngineException.errKey → 本地化文案的唯一映射。`runAction` 内部用它渲染
/// SnackBar；不经过 `runAction`（例如保存失败需要保留对话框、行内展示错误，
/// 不能先关闭再弹 SnackBar）的屏幕也应复用这个函数，而不是各自把
/// EngineException 的 errKey/参数 Map 原样 toString() 给用户看。
String engineErrorText(BuildContext context, EngineException error) {
  final l10n = AppLocalizations.of(context);
  return switch (error.errKey) {
    errProviderMissing => l10n.errProviderMissing,
    errModelMissing => l10n.errModelMissing,
    errNetwork => l10n.errNetwork,
    errLlmFormat => l10n.errLlmFormat,
    errCanceled => l10n.errCanceled,
    errAppRestart => l10n.errAppRestart,
    errFileTooLarge => l10n.errFileTooLarge,
    errFileType => l10n.errFileType,
    errRegexInvalid => l10n.errRegexInvalid,
    errNoChapters => l10n.errNoChapters,
    errPlatformComposer => l10n.errPlatformComposer,
    errDbTableClearForbidden => l10n.errDbTableClearForbidden,
    _ => error.message,
  };
}

/// 带 token 的后端图片。统一圆角、加载渐入、错误占位。
class MediaImage extends StatelessWidget {
  final String? relativeUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;

  const MediaImage(
    this.relativeUrl, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (relativeUrl == null || relativeUrl!.isEmpty) {
      return _placeholder(
        context,
        Icon(Icons.image_outlined, color: context.df.textLo, size: 28),
      );
    }
    // Web 构建无本地文件能力（spec：Web 降级为 UI 预览）
    if (kIsWeb) {
      return _placeholder(
        context,
        Icon(Icons.image_not_supported_outlined,
            color: context.df.textLo, size: 28),
      );
    }
    return Consumer(builder: (context, ref, _) {
      final abs = ref.watch(engineProvider).mediaAbsPath(relativeUrl!);
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(abs),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSync) => wasSync
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 250),
                  child: child,
                ),
          errorBuilder: (context, e, _) => _placeholder(
            context,
            Icon(Icons.broken_image_outlined,
                color: context.df.textLo, size: 28),
          ),
        ),
      );
    });
  }

  Widget _placeholder(BuildContext context, Widget child) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.df.bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: context.df.stroke),
        ),
        child: Center(child: child),
      );
}

class ImageTakesStrip extends StatelessWidget {
  final AsyncValue<List<ImageTake>> value;
  final ValueChanged<ImageTake> onSelect;

  const ImageTakesStrip({
    super.key,
    required this.value,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.df.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 15, color: context.df.textLo),
              const SizedBox(width: 6),
              Text(
                l10n.imageVersionsTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.df.textMid,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          value.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            data: (takes) {
              if (takes.isEmpty) {
                return SizedBox(
                  height: 74,
                  child: Center(
                    child: Text(
                      l10n.imageVersionsEmpty,
                      style: TextStyle(fontSize: 12, color: context.df.textLo),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: takes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final take = takes[index];
                    return _ImageTakeTile(
                      take: take,
                      label: l10n.imageVersionLabel(takes.length - index),
                      onTap: take.selected ? null : () => onSelect(take),
                    );
                  },
                ),
              );
            },
            loading: () => SizedBox(
              height: 74,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.df.primary,
                  ),
                ),
              ),
            ),
            error: (e, _) => SizedBox(
              height: 74,
              child: Center(
                child: Text(
                  e.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.df.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageTakeTile extends StatelessWidget {
  final ImageTake take;
  final String label;
  final VoidCallback? onTap;

  const _ImageTakeTile({
    required this.take,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      child: Material(
        color: take.selected
            ? context.df.primary.withValues(alpha: 0.1)
            : context.df.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: take.selected ? context.df.primary : context.df.stroke,
                width: take.selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: MediaImage(take.imagePath, radius: 6),
                      ),
                      if (take.selected)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Icon(Icons.check_circle_rounded,
                              size: 16, color: context.df.primary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color:
                        take.selected ? context.df.primary : context.df.textMid,
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

Future<String?> showRepaintInstructionDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (context) => const _RepaintInstructionDialog(),
  );
}

class _RepaintInstructionDialog extends StatefulWidget {
  const _RepaintInstructionDialog();

  @override
  State<_RepaintInstructionDialog> createState() =>
      _RepaintInstructionDialogState();
}

class _RepaintInstructionDialogState extends State<_RepaintInstructionDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = l10n.repaintInstructionRequired);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.repaintImageTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: l10n.repaintImageHint,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.brush_outlined, size: 18),
          label: Text(l10n.repaintAction),
        ),
      ],
    );
  }
}
