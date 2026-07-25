import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

void showDFToast(BuildContext context, String message, {bool isError = false}) {
  final df = context.df;
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) {
      return _ToastWidget(
        message: message,
        isError: isError,
        df: df,
        onDismissed: () {
          if (entry.mounted) entry.remove();
        },
      );
    },
  );

  overlay.insert(entry);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final DFColors df;
  final VoidCallback onDismissed;

  const _ToastWidget({
    required this.message,
    required this.isError,
    required this.df,
    required this.onDismissed,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  /// 停留计时器必须留住引用：页面在 3 秒内被关掉时要能取消它，
  /// 否则定时器会活过整棵组件树（测试里直接报「Timer is still pending」，
  /// 实际使用中则是一次泄漏 + 永远移不掉的浮层）。
  Timer? _dwell;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _slide = Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    _dwell = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _controller.reverse().then((_) {
        if (mounted) widget.onDismissed();
      });
    });
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: FadeTransition(
              opacity: _opacity,
              child: SlideTransition(
                position: _slide,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.isError ? widget.df.danger : widget.df.surface,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: widget.isError
                        ? null
                        : Border.all(color: widget.df.stroke),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isError)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.error_outline,
                              color: Colors.white, size: 18),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.info_outline,
                              color: widget.df.primary, size: 18),
                        ),
                      Text(
                        widget.message,
                        style: TextStyle(
                          color: widget.isError
                              ? Colors.white
                              : widget.df.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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
