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
    barrierColor: Colors.black.withValues(alpha: 0.35),
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
          // 注：不用 BackdropFilter——它在 showGeneralDialog 的缩放/淡入过渡动画期间
          // 逐帧重新采样模糊，跟动画同时触发会导致渲染树错乱（弹窗打不开、点哪里
          // 都可能卡顿）。背景色本身已经是 92% 不透明度，去掉模糊视觉损失很小。
          child: SizedBox(
            width: screenWidth * widthFactor,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.stroke.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 40,
                      spreadRadius: 2,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 20, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.commonClose,
                              style: IconButton.styleFrom(
                                backgroundColor: colors.surfaceMuted,
                                padding: const EdgeInsets.all(8),
                              ),
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: colors.stroke.withValues(alpha: 0.4)),
                      Flexible(child: builder(context)),
                    ],
                  ),
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
