import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

class StartupFailure {
  final Object cause;
  final String? dataDirectory;

  const StartupFailure({required this.cause, this.dataDirectory});
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.all(compact ? 24 : 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.folder_off_outlined, size: 42),
                  const SizedBox(height: 20),
                  Text(
                    l10n.bootstrapFailureTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.bootstrapFailureMessage,
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
