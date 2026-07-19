import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import '../../util/l10n_ext.dart';

/// 制作画布的本地一次性操作引导。
///
/// 组件只展示步骤并报告结束事件；是否首次显示及完成状态由制作页负责持久化。
class ProductionGuideOverlay extends StatefulWidget {
  final bool compact;
  final List<GlobalKey> targets;
  final VoidCallback onComplete;

  const ProductionGuideOverlay({
    super.key,
    required this.compact,
    required this.targets,
    required this.onComplete,
  }) : assert(targets.length == 4);

  @override
  State<ProductionGuideOverlay> createState() => _ProductionGuideOverlayState();
}

class _ProductionGuideOverlayState extends State<ProductionGuideOverlay> {
  var _step = 0;
  var _finished = false;
  final _overlayKey = GlobalKey();
  Rect? _target;
  var _targetMeasurementQueued = false;

  @override
  void initState() {
    super.initState();
    _scheduleTargetMeasurement();
  }

  @override
  void didUpdateWidget(covariant ProductionGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact) {
      _target = null;
    }
    _scheduleTargetMeasurement();
  }

  void _complete() {
    if (_finished) return;
    setState(() => _finished = true);
    widget.onComplete();
  }

  void _next() {
    if (_step == _guideStepCount - 1) {
      _complete();
      return;
    }
    setState(() {
      _step++;
      _target = null;
    });
    _scheduleTargetMeasurement();
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step--;
      _target = null;
    });
    _scheduleTargetMeasurement();
  }

  void _scheduleTargetMeasurement() {
    if (widget.compact || _targetMeasurementQueued) return;
    _targetMeasurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _targetMeasurementQueued = false;
      if (!mounted || _finished) return;
      final nextTarget = _targetRect();
      if (nextTarget != _target) setState(() => _target = nextTarget);
    });
  }

  Rect? _targetRect() {
    final target = widget.targets[_step].currentContext?.findRenderObject();
    final overlay = _overlayKey.currentContext?.findRenderObject();
    if (target is! RenderBox || overlay is! RenderBox || !target.hasSize) {
      return null;
    }
    final targetOrigin = target.localToGlobal(Offset.zero);
    final overlayOrigin = overlay.localToGlobal(Offset.zero);
    return (targetOrigin - overlayOrigin) & target.size;
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, _) {
      _scheduleTargetMeasurement();
      final l10n = context.l10n;
      final guide = _GuideCopy.from(context, _step, compact: widget.compact);
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _complete();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          key: const Key('production-guide'),
          label: l10n.productionGuideTitle,
          container: true,
          child: SizedBox.expand(
            key: _overlayKey,
            child: widget.compact
                ? _CompactGuide(
                    guide: guide,
                    step: _step,
                    onBack: _back,
                    onNext: _next,
                    onComplete: _complete,
                  )
                : _DesktopGuide(
                    guide: guide,
                    step: _step,
                    target: _target,
                    onBack: _back,
                    onNext: _next,
                    onComplete: _complete,
                  ),
          ),
        ),
      );
    });
  }
}

const _guideStepCount = 4;

class _GuideCopy {
  final IconData icon;
  final String title;
  final String body;

  const _GuideCopy({
    required this.icon,
    required this.title,
    required this.body,
  });

  factory _GuideCopy.from(
    BuildContext context,
    int step, {
    required bool compact,
  }) {
    final l10n = context.l10n;
    return switch (step) {
      0 => _GuideCopy(
          icon: Icons.view_carousel_outlined,
          title: l10n.productionGuideEpisodeTitle,
          body: l10n.productionGuideEpisodeBody,
        ),
      1 => _GuideCopy(
          icon: Icons.refresh_rounded,
          title: l10n.productionGuideRefreshTitle,
          body: l10n.productionGuideRefreshBody,
        ),
      2 => _GuideCopy(
          icon: Icons.account_tree_outlined,
          title: l10n.productionGuideLayoutTitle,
          body: l10n.productionGuideLayoutBody,
        ),
      _ => _GuideCopy(
          icon: Icons.pan_tool_outlined,
          title: l10n.productionGuideCanvasTitle,
          body: compact
              ? l10n.productionGuideMobileLayoutBody
              : l10n.productionGuideCanvasBody,
        ),
    };
  }
}

class _DesktopGuide extends StatelessWidget {
  final _GuideCopy guide;
  final int step;
  final Rect? target;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onComplete;

  const _DesktopGuide({
    required this.guide,
    required this.step,
    required this.target,
    required this.onBack,
    required this.onNext,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cardPosition = _cardPosition(constraints.biggest, target);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(
                    painter: _GuideScrimPainter(hole: target?.inflate(6)),
                  ),
                ),
              ),
              if (target != null)
                Positioned.fromRect(
                  rect: target!.inflate(6),
                  child: IgnorePointer(
                    key: const Key('production-guide-highlight'),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: context.df.primary, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              Positioned(
                key: const Key('production-guide-desktop-card'),
                left: cardPosition.dx,
                top: cardPosition.dy,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(360, constraints.maxWidth - 32),
                  ),
                  child: _GuideCard(
                    guide: guide,
                    step: step,
                    onBack: onBack,
                    onNext: onNext,
                    onComplete: onComplete,
                  ),
                ),
              ),
            ],
          );
        },
      );

  Offset _cardPosition(Size viewport, Rect? target) {
    const cardWidth = 360.0;
    const cardHeight = 268.0;
    const gutter = 16.0;
    var left = target == null
        ? viewport.width - cardWidth - 24
        : target.right + gutter;
    var top = target == null ? 24.0 : target.top;
    if (left + cardWidth > viewport.width - gutter && target != null) {
      left = target.left - cardWidth - gutter;
    }
    if (left < gutter) {
      left = math.max(gutter, (viewport.width - cardWidth) / 2);
      if (target != null) top = target.bottom + gutter;
    }
    return Offset(
      left.clamp(gutter, math.max(gutter, viewport.width - cardWidth - gutter)),
      top.clamp(
          gutter, math.max(gutter, viewport.height - cardHeight - gutter)),
    );
  }
}

class _CompactGuide extends StatelessWidget {
  final _GuideCopy guide;
  final int step;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onComplete;

  const _CompactGuide({
    required this.guide,
    required this.step,
    required this.onBack,
    required this.onNext,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const Key('production-guide-compact'),
        color: context.df.bg,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              key: const Key('production-guide-compact-scroll'),
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 48),
                ),
                child: _GuideCard(
                  guide: guide,
                  step: step,
                  onBack: onBack,
                  onNext: onNext,
                  onComplete: onComplete,
                  flat: true,
                ),
              ),
            );
          }),
        ),
      );
}

class _GuideCard extends StatelessWidget {
  final _GuideCopy guide;
  final int step;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onComplete;
  final bool flat;

  const _GuideCard({
    required this.guide,
    required this.step,
    required this.onBack,
    required this.onNext,
    required this.onComplete,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.productionGuideStepCounter(step + 1, _guideStepCount),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.df.textMid,
              ),
        ),
        const SizedBox(height: 18),
        Icon(guide.icon, color: context.df.primary, size: 34),
        const SizedBox(height: 14),
        Text(guide.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          guide.body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.df.textMid,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            TextButton(
              key: const Key('production-guide-skip'),
              onPressed: onComplete,
              child: Text(l10n.productionGuideSkip),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('production-guide-back'),
                  onPressed: step == 0 ? null : onBack,
                  child: Text(l10n.productionGuideBack),
                ),
                FilledButton(
                  key: Key(step == _guideStepCount - 1
                      ? 'production-guide-finish'
                      : 'production-guide-next'),
                  onPressed: step == _guideStepCount - 1 ? onComplete : onNext,
                  child: Text(step == _guideStepCount - 1
                      ? l10n.productionGuideFinish
                      : l10n.productionGuideNext),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    return Material(
      color: context.df.surface,
      elevation: flat ? 0 : 12,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: content,
      ),
    );
  }
}

class _GuideScrimPainter extends CustomPainter {
  final Rect? hole;

  const _GuideScrimPainter({required this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      path.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(8)));
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
        path, Paint()..color = Colors.black.withValues(alpha: 0.62));
  }

  @override
  bool shouldRepaint(covariant _GuideScrimPainter oldDelegate) =>
      oldDelegate.hole != hole;
}
