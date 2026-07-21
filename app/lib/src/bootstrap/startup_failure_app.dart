import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

class StartupFailure {
  final Object cause;
  final String? dataDirectory;

  const StartupFailure({required this.cause, this.dataDirectory});

  /// 权限/磁盘 IO 类失败——重试有意义（比如用户腾出空间或修好权限后）。
  /// 其余一律归为"其他"（数据库损坏、schema 版本不兼容等）：这类原因下
  /// 无脑重试大概率会一直失败，文案不应该继续暗示"检查磁盘空间和权限"。
  bool get isFileSystemFailure => cause is FileSystemException;
}

class StartupFailureApp extends StatelessWidget {
  final StartupFailure failure;
  final Future<void> Function() onRetry;
  final VoidCallback? onExit;

  const StartupFailureApp({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DramaFlow',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: _StartupFailurePage(
        failure: failure,
        onRetry: onRetry,
        onExit: onExit,
      ),
    );
  }
}

class _StartupFailurePage extends StatefulWidget {
  final StartupFailure failure;
  final Future<void> Function() onRetry;
  final VoidCallback? onExit;

  const _StartupFailurePage({
    required this.failure,
    required this.onRetry,
    required this.onExit,
  });

  @override
  State<_StartupFailurePage> createState() => _StartupFailurePageState();
}

class _StartupFailurePageState extends State<_StartupFailurePage> {
  bool _retrying = false;
  bool _detailsExpanded = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await widget.onRetry();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final directory = widget.failure.dataDirectory;
    // 只有权限/磁盘 IO 类失败才继续暗示"检查磁盘空间和权限、重试"；其余原因
    // （比如数据库损坏、schema 版本不兼容）重试大概率无效，文案不应该误导。
    final isFileSystemFailure = widget.failure.isFileSystemFailure;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 24 : 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isFileSystemFailure
                        ? Icons.folder_off_outlined
                        : Icons.error_outline,
                    size: 42,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isFileSystemFailure
                        ? l10n.bootstrapFailureTitle
                        : l10n.bootstrapFailureTitleGeneric,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isFileSystemFailure
                        ? l10n.bootstrapFailureMessage
                        : l10n.bootstrapFailureMessageGeneric,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (directory != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.bootstrapFailureDirectory,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      directory,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _FailureDetails(
                    cause: widget.failure.cause,
                    expanded: _detailsExpanded,
                    onToggle: () =>
                        setState(() => _detailsExpanded = !_detailsExpanded),
                  ),
                  const SizedBox(height: 28),
                  if (compact)
                    _FailureActions(
                      retrying: _retrying,
                      onRetry: _retry,
                      onExit: widget.onExit,
                    )
                  else
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _retrying ? null : _retry,
                          child: Text(l10n.bootstrapFailureRetry),
                        ),
                        if (widget.onExit != null) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: widget.onExit,
                            child: Text(l10n.bootstrapFailureExit),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailureActions extends StatelessWidget {
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback? onExit;

  const _FailureActions({
    required this.retrying,
    required this.onRetry,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: retrying ? null : onRetry,
          child: Text(l10n.bootstrapFailureRetry),
        ),
        if (onExit != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onExit,
            child: Text(l10n.bootstrapFailureExit),
          ),
        ],
      ],
    );
  }
}

/// 可展开的"详细信息"：展示 [cause] 的真实文本，不只是 debugPrint。
///
/// 这是诚实展示错误的最低要求——不做分类判断也至少要让用户（或帮用户远程排障
/// 的人）看到真实异常文本，而不是只有笼统的"检查磁盘空间和权限"提示。
class _FailureDetails extends StatelessWidget {
  final Object cause;
  final bool expanded;
  final VoidCallback onToggle;

  const _FailureDetails({
    required this.cause,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  expanded
                      ? l10n.bootstrapFailureHideDetails
                      : l10n.bootstrapFailureShowDetails,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              cause.toString(),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }
}
