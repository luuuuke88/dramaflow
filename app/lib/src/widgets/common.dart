import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/util.dart';
import '../state/providers.dart';
import '../theme.dart';

/// 状态 → 视觉语义 的唯一映射，全 App 统一。
class StatusChip extends StatelessWidget {
  final String status; // none/draft/queued/running/done/failed/canceled
  final String? errorTooltip;
  final bool dense;

  const StatusChip(this.status,
      {super.key, this.errorTooltip, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      'queued' => ('排队中', context.df.blue, Icons.schedule_rounded),
      'running' => ('生成中', context.df.primary, Icons.autorenew_rounded),
      'done' => ('已完成', context.df.green, Icons.check_circle_rounded),
      'failed' => ('失败', context.df.red, Icons.error_rounded),
      'canceled' => ('已取消', context.df.grey, Icons.block_rounded),
      'draft' => ('待生成', context.df.grey, Icons.edit_note_rounded),
      _ => ('未生成', context.df.grey, Icons.circle_outlined),
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
          if (status == 'running')
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
                    label: const Text('重试'),
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
Future<void> runAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  // 在 await 之前取全局 notifier：请求期间 widget 可能被卸载（关对话框/切页），
  // 卸载后再用 widget 的 ref 会被 Riverpod 3 直接抛 StateError
  final jobsNotifier = ref.read(activeJobsProvider.notifier);
  try {
    await action();
    jobsNotifier.poke();
    if (successMessage != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(successMessage),
            duration: const Duration(seconds: 2)),
      );
    }
  } on EngineException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message, style: const TextStyle(color: Colors.white)),
        backgroundColor: context.df.red,
        duration: const Duration(seconds: 4),
      ));
    }
  }
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
