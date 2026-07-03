import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/theme.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DramaFlowWebPreviewApp());
}

class DramaFlowWebPreviewApp extends StatelessWidget {
  const DramaFlowWebPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DramaFlow',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
        Locale('ja'),
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const _WebPreviewPage(),
    );
  }
}

class _WebPreviewPage extends StatelessWidget {
  const _WebPreviewPage();

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    return Scaffold(
      backgroundColor: df.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: EdgeInsets.all(compact ? 20 : 32),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: df.surface,
                  border: Border.all(color: df.stroke),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 22 : 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.movie_creation_outlined,
                              color: df.primary, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'DramaFlow Web',
                            style: TextStyle(
                              color: df.textHi,
                              fontSize: compact ? 22 : 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.webPreviewBuildableTitle,
                        style: TextStyle(
                          color: df.textHi,
                          fontSize: compact ? 18 : 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.webPreviewMessage,
                        style: TextStyle(
                          color: df.textMid,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Badge(
                              label: l10n.webPreviewMacClient,
                              color: df.success),
                          _Badge(
                              label: l10n.webPreviewIosClient,
                              color: df.success),
                          _Badge(
                              label: l10n.webPreviewAndroidClient,
                              color: df.success),
                          _Badge(
                              label: l10n.webPreviewEnginePending,
                              color: df.warning),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
