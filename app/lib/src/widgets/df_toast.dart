import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 提示条的定位标识：测试与自动化按它找当前提示，不必依赖内部结构。
const dfToastKey = Key('df-toast');

/// 当前正在显示的提示条。全应用同一时刻只留一条：连着做几个动作时，
/// 若每条都堆上去会糊成一片，最后一条才是用户关心的。
OverlayEntry? _currentToast;

/// 全应用统一的提示条：一律从**顶部**滑出。
///
/// 这里取代了 Flutter 默认的 SnackBar（从底部弹出）——两套并存时，
/// 同一个软件里有的提示从上面来、有的从下面来，很跳。
void showDFToast(BuildContext context, String message, {bool isError = false}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  // 主题扩展缺席时退回一套中性配色：提示条是最外围的反馈，
  // 绝不该因为拿不到配色就把整个界面拖崩。
  final df = Theme.of(context).extension<DFColors>() ??
      DFColors.light(primary: Theme.of(context).colorScheme.primary);

  _currentToast?.remove();
  _currentToast = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return _ToastWidget(
        key: dfToastKey,
        message: message,
        isError: isError,
        df: df,
        onDismissed: () {
          if (entry.mounted) entry.remove();
          if (identical(_currentToast, entry)) _currentToast = null;
        },
      );
    },
  );

  _currentToast = entry;
  overlay.insert(entry);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final DFColors df;
  final VoidCallback onDismissed;

  const _ToastWidget({
    super.key,
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
      // 提示条是被动通知，没有任何可点内容：必须让点击穿透过去。
      // 顶部提示会压在正文上方，若还拦截手势，用户就会点不动被它盖住的东西
      //（底部 SnackBar 时代不存在这个问题，换到顶部才暴露出来）。
      child: IgnorePointer(
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: FadeTransition(
                opacity: _opacity,
                child: SlideTransition(
                  position: _slide,
                  child: Container(
                    // 窄屏上长文案原本会把提示条撑出屏幕。这里给出上限并留出
                    // 两侧边距，文字改为换行显示。
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        520,
                        MediaQuery.sizeOf(context).width - 32,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color:
                          widget.isError ? widget.df.danger : widget.df.surface,
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
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.isError
                                  ? Colors.white
                                  : widget.df.textPrimary,
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
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
      ),
    );
  }
}
