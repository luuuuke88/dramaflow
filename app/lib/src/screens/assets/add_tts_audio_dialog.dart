import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/tts.dart';
import '../../state/providers.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<bool?> showAddTtsAudioDialog(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.assetsGenerateSpeech,
    desktopWidthFactor: 0.42,
    builder: (c) => _AddTtsAudioBody(projectId: projectId, ref: ref),
  );
}

class _AddTtsAudioBody extends StatefulWidget {
  final int projectId;
  final WidgetRef ref;
  const _AddTtsAudioBody({required this.projectId, required this.ref});

  @override
  State<_AddTtsAudioBody> createState() => _AddTtsAudioBodyState();
}

class _AddTtsAudioBodyState extends State<_AddTtsAudioBody> {
  final TextEditingController _name = TextEditingController(text: 'alloy');
  final TextEditingController _sex = TextEditingController();
  final TextEditingController _describe = TextEditingController();
  final TextEditingController _text = TextEditingController();
  final TextEditingController _voice = TextEditingController(text: 'alloy');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _sex.dispose();
    _describe.dispose();
    _text.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.assetsAddAudioNamePh);
      return;
    }
    if (_text.text.trim().isEmpty) {
      _toast(l10n.assetsTtsTextRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.ref.read(engineProvider).addSynthesizedAudioAsset(
            projectId: widget.projectId,
            name: _name.text.trim(),
            sex: _sex.text.trim(),
            describe: _describe.text.trim(),
            text: _text.text.trim(),
            voice: _voice.text.trim().isEmpty ? null : _voice.text.trim(),
          );
      if (!mounted) return;
      _toast(l10n.assetsAddAddSuccess);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(children: [
            TextField(
              key: const Key('tts-audio-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.assetsAudioName,
                hintText: l10n.assetsAddAudioNamePh,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tts-audio-sex'),
              controller: _sex,
              decoration: InputDecoration(
                labelText: l10n.assetsSex,
                hintText: l10n.assetsAddSexPh,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tts-audio-describe'),
              controller: _describe,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.assetsColDescribe,
                hintText: l10n.assetsAddAudioDescPh,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tts-audio-text'),
              controller: _text,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.assetsTtsText,
                hintText: l10n.assetsTtsTextPh,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tts-audio-voice'),
              controller: _voice,
              decoration: InputDecoration(
                labelText: l10n.assetsTtsVoice,
                hintText: l10n.assetsTtsVoicePh,
              ),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.assetsCancelBtn),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.record_voice_over_outlined, size: 18),
            label: Text(l10n.assetsTtsGenerate),
          ),
        ]),
      ),
    ]);
  }
}
