import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../util/l10n_ext.dart';

/// 原版 hello.vue 的跨端等价入口：首次启动时引导用户到已有的模型与绑定设置。
///
/// 引导本身不探测网络、不写凭证，也不发起任何模型或视频请求。
class FirstRunGuide extends StatefulWidget {
  final VoidCallback onComplete;
  final ValueChanged<String> onOpenSettings;
  final ValueChanged<String>? onLocaleChanged;

  const FirstRunGuide({
    super.key,
    required this.onComplete,
    required this.onOpenSettings,
    this.onLocaleChanged,
  });

  @override
  State<FirstRunGuide> createState() => _FirstRunGuideState();
}

class _FirstRunGuideState extends State<FirstRunGuide> {
  int _step = 0;

  void _next() => setState(() => _step = (_step + 1).clamp(0, 3));
  void _previous() => setState(() => _step = (_step - 1).clamp(0, 3));

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final isWelcome = _step == 0;

    return ColoredBox(
      color: context.df.bg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              width: double.infinity,
              height: compact ? double.infinity : null,
              margin: compact ? EdgeInsets.zero : const EdgeInsets.all(24),
              padding: EdgeInsets.fromLTRB(24, compact ? 32 : 36, 24, 24),
              decoration: BoxDecoration(
                color: context.df.surface,
                border: compact ? null : Border.all(color: context.df.stroke),
                borderRadius:
                    compact ? BorderRadius.zero : BorderRadius.circular(8),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: isWelcome
                    ? _Welcome(
                        key: const ValueKey('welcome'),
                        onStart: _next,
                        onSkip: widget.onComplete,
                        onLocaleChanged: widget.onLocaleChanged,
                      )
                    : _GuideStep(
                        key: ValueKey('step-$_step'),
                        step: _step,
                        onPrevious: _previous,
                        onNext: _next,
                        onComplete: widget.onComplete,
                        onOpenSettings: widget.onOpenSettings,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onSkip;
  final ValueChanged<String>? onLocaleChanged;

  const _Welcome({
    super.key,
    required this.onStart,
    required this.onSkip,
    this.onLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
            key: const Key('onboarding-language'),
            tooltip: l10n.onboardingLanguage,
            icon: const Icon(Icons.translate_rounded),
            onSelected: onLocaleChanged,
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('onboarding-language-zh'),
                value: 'zh',
                child: Text(l10n.onboardingLanguageZh),
              ),
              PopupMenuItem(
                key: const Key('onboarding-language-en'),
                value: 'en',
                child: Text(l10n.onboardingLanguageEn),
              ),
              PopupMenuItem(
                key: const Key('onboarding-language-ja'),
                value: 'ja',
                child: Text(l10n.onboardingLanguageJa),
              ),
            ],
          ),
        ),
        const Spacer(),
        Icon(Icons.auto_stories_rounded, size: 64, color: context.df.primary),
        const SizedBox(height: 24),
        Text(l10n.onboardingWelcomeTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(l10n.onboardingWelcomeBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.df.textMid,
                  height: 1.5,
                )),
        const SizedBox(height: 32),
        FilledButton.icon(
          key: const Key('onboarding-start'),
          onPressed: onStart,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(l10n.onboardingStart),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('onboarding-skip-welcome'),
          onPressed: onSkip,
          child: Text(l10n.onboardingSkip),
        ),
        const Spacer(),
      ],
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int step;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onComplete;
  final ValueChanged<String> onOpenSettings;

  const _GuideStep({
    super.key,
    required this.step,
    required this.onPrevious,
    required this.onNext,
    required this.onComplete,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isModels = step == 1;
    final isBindings = step == 2;
    final title = isModels
        ? l10n.onboardingModelsTitle
        : isBindings
            ? l10n.onboardingBindingsTitle
            : l10n.onboardingCompleteTitle;
    final body = isModels
        ? l10n.onboardingModelsBody
        : isBindings
            ? l10n.onboardingBindingsBody
            : l10n.onboardingCompleteBody;
    final icon = isModels
        ? Icons.cloud_queue_rounded
        : isBindings
            ? Icons.hub_outlined
            : Icons.check_circle_outline_rounded;
    final actionLabel =
        isModels ? l10n.onboardingOpenProviders : l10n.onboardingOpenBindings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepProgress(current: step),
        const Spacer(),
        Icon(icon,
            size: 52,
            color: step == 3 ? context.df.success : context.df.primary),
        const SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.df.textMid,
                  height: 1.5,
                )),
        if (step < 3) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: Key('onboarding-open-${isModels ? 'providers' : 'bindings'}'),
            onPressed: () =>
                onOpenSettings(isModels ? 'providers' : 'bindings'),
            icon: const Icon(Icons.settings_outlined),
            label: Text(actionLabel),
          ),
        ],
        const Spacer(),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: onPrevious,
              child: Text(l10n.onboardingPrevious),
            ),
            Wrap(
              spacing: 8,
              children: [
                if (step < 3) ...[
                  TextButton(
                    key: const Key('onboarding-skip'),
                    onPressed: onComplete,
                    child: Text(l10n.onboardingSkip),
                  ),
                  FilledButton(
                    key: const Key('onboarding-next'),
                    onPressed: onNext,
                    child: Text(l10n.onboardingNext),
                  ),
                ] else
                  FilledButton(
                    key: const Key('onboarding-finish'),
                    onPressed: onComplete,
                    child: Text(l10n.onboardingFinish),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _StepProgress extends StatelessWidget {
  final int current;

  const _StepProgress({required this.current});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var index = 1; index <= 3; index++) ...[
            _StepDot(active: index <= current, label: '$index'),
            if (index < 3)
              Expanded(
                child: Container(
                  height: 1,
                  color:
                      index < current ? context.df.primary : context.df.stroke,
                ),
              ),
          ],
        ],
      );
}

class _StepDot extends StatelessWidget {
  final bool active;
  final String label;

  const _StepDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? context.df.primary : context.df.surfaceMuted,
          shape: BoxShape.circle,
        ),
        child: Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: active ? Colors.white : context.df.textMid,
                )),
      );
}
