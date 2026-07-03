import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';

Future<T?> showDFAdaptiveDialog<T>(
  BuildContext c, {
  required String title,
  required WidgetBuilder builder,
  double desktopWidthFactor = .6,
}) {
  final width = MediaQuery.sizeOf(c).width;
  if (width < 840) {
    return Navigator.of(c).push<T>(
      PageRouteBuilder<T>(
        fullscreenDialog: true,
        transitionDuration: DFTokens.emphasized320,
        reverseTransitionDuration: DFTokens.standard200,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                tooltip: context.l10n.commonClose,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            body: SafeArea(child: builder(context)),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: DFTokens.curve,
            reverseCurve: DFTokens.curve,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  return showGeneralDialog<T>(
    context: c,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(c).modalBarrierDismissLabel,
    transitionDuration: DFTokens.standard200,
    pageBuilder: (context, animation, secondaryAnimation) {
      final colors = context.df;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final widthFactor = desktopWidthFactor.clamp(0.2, 0.96).toDouble();
      return Center(
        child: Dialog(
          elevation: 0,
          insetPadding: const EdgeInsets.all(DFTokens.s32),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: SizedBox(
            width: screenWidth * widthFactor,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(DFTokens.radiusCard),
                border: Border.all(color: colors.stroke),
                boxShadow: DFTokens.dialog,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DFTokens.radiusCard),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DFTokens.s20,
                        DFTokens.s16,
                        DFTokens.s12,
                        DFTokens.s12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: DFTokens.title20w700
                                  .copyWith(color: colors.textPrimary),
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.commonClose,
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.stroke),
                    Flexible(child: builder(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: DFTokens.curve,
        reverseCurve: DFTokens.curve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
