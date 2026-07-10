import 'package:flutter/material.dart';

import '../../engine/video_request.dart';
import '../../engine/video_track.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<VideoRequestDraft?> showVideoRequestDialog(
  BuildContext context, {
  required VideoRequestDraft initial,
  required VideoModelCapabilities capabilities,
  required List<VideoReferenceCandidate> candidates,
}) {
  if (capabilities.modes.isEmpty) return Future.value(null);
  return showDFAdaptiveDialog<VideoRequestDraft>(
    context,
    title: context.l10n.workbenchVideoParameters,
    desktopWidthFactor: .48,
    builder: (_) => _VideoRequestDialog(
      initial: initial,
      capabilities: capabilities,
      candidates: candidates,
    ),
  );
}

class _VideoRequestDialog extends StatefulWidget {
  final VideoRequestDraft initial;
  final VideoModelCapabilities capabilities;
  final List<VideoReferenceCandidate> candidates;

  const _VideoRequestDialog({
    required this.initial,
    required this.capabilities,
    required this.candidates,
  });

  @override
  State<_VideoRequestDialog> createState() => _VideoRequestDialogState();
}

class _VideoRequestDialogState extends State<_VideoRequestDialog> {
  late VideoMode _mode;
  late int _duration;
  late String _resolution;
  late String _ratio;
  late bool _generateAudio;
  VideoReferenceCandidate? _lastFrame;
  final Set<String> _multiReferenceKeys = {};

  List<VideoMode> get _modes => widget.capabilities.modes.toList()
    ..sort((left, right) => left.wireValue.compareTo(right.wireValue));

  List<int> get _durations => widget.capabilities.durations.toList()..sort();

  List<String> get _resolutions =>
      widget.capabilities.resolutions.toList()..sort();

  List<String> get _ratios => widget.capabilities.ratios.toList()..sort();

  List<VideoReferenceCandidate> get _imageCandidates => widget.candidates
      .where((candidate) => candidate.source.mediaType == 'image')
      .toList();

  VideoReferenceSource? get _fixedFirstFrame {
    for (final reference in widget.initial.references) {
      if (reference.role == 'first_frame' && reference.mediaType == 'image') {
        return reference;
      }
    }
    for (final candidate in _imageCandidates) {
      if (candidate.source.role == 'first_frame') {
        return _withRole(candidate.source, 'first_frame');
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.capabilities.supports(widget.initial.mode)
        ? widget.initial.mode
        : _modes.first;
    _duration = widget.capabilities.durations.contains(widget.initial.duration)
        ? widget.initial.duration
        : _durations.first;
    _resolution =
        widget.capabilities.resolutions.contains(widget.initial.resolution)
            ? widget.initial.resolution
            : _resolutions.first;
    _ratio = widget.capabilities.ratios.contains(widget.initial.ratio)
        ? widget.initial.ratio
        : _ratios.first;
    _generateAudio = widget.capabilities.audio == 'required'
        ? true
        : widget.capabilities.audio == 'optional' &&
            widget.initial.generateAudio;

    for (final candidate in widget.candidates) {
      final source = candidate.source;
      if (widget.initial.references.any((reference) =>
          reference.sourceType == source.sourceType &&
          reference.sourceId == source.sourceId &&
          reference.role == 'last_frame')) {
        _lastFrame = candidate;
      }
      if (widget.initial.references.any((reference) =>
          reference.sourceType == source.sourceType &&
          reference.sourceId == source.sourceId &&
          reference.role == _referenceRole(source.mediaType))) {
        _multiReferenceKeys.add(_candidateKey(candidate));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSave = switch (_mode) {
      VideoMode.firstFrame => _fixedFirstFrame != null,
      VideoMode.firstLastFrame =>
        _fixedFirstFrame != null && _lastFrame != null,
      VideoMode.multiReference => _multiReferenceKeys.isNotEmpty,
      VideoMode.text => true,
    };
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<VideoMode>(
                  key: const ValueKey('video-request-mode'),
                  initialValue: _mode,
                  decoration: InputDecoration(labelText: l10n.videoRequestMode),
                  items: [
                    for (final mode in _modes)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(mode.wireValue),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode == null) return;
                    setState(() => _mode = mode);
                  },
                ),
                const SizedBox(height: 12),
                _choiceField<int>(
                  key: const ValueKey('video-request-duration'),
                  label: l10n.videoRequestDuration,
                  value: _duration,
                  options: _durations,
                  labelFor: (value) => '$value',
                  onChanged: (value) => setState(() => _duration = value),
                ),
                const SizedBox(height: 12),
                _choiceField<String>(
                  key: const ValueKey('video-request-resolution'),
                  label: l10n.videoRequestResolution,
                  value: _resolution,
                  options: _resolutions,
                  labelFor: (value) => value,
                  onChanged: (value) => setState(() => _resolution = value),
                ),
                const SizedBox(height: 12),
                _choiceField<String>(
                  key: const ValueKey('video-request-ratio'),
                  label: l10n.videoRequestRatio,
                  value: _ratio,
                  options: _ratios,
                  labelFor: (value) => value,
                  onChanged: (value) => setState(() => _ratio = value),
                ),
                if (widget.capabilities.audio != 'none') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('video-request-provider-audio'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.videoRequestProviderAudio),
                    value: widget.capabilities.audio == 'required'
                        ? true
                        : _generateAudio,
                    onChanged: widget.capabilities.audio == 'optional'
                        ? (value) => setState(() => _generateAudio = value)
                        : null,
                  ),
                ],
                const SizedBox(height: 8),
                _buildReferences(context),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('video-request-save'),
                    onPressed: canSave
                        ? () => Navigator.of(context).pop(_result())
                        : null,
                    child: Text(l10n.commonSave),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferences(BuildContext context) {
    final l10n = context.l10n;
    switch (_mode) {
      case VideoMode.text:
        return const SizedBox.shrink();
      case VideoMode.firstFrame:
        return _fixedFrameTile(l10n.videoRequestFirstFrame);
      case VideoMode.firstLastFrame:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fixedFrameTile(l10n.videoRequestFirstFrame),
            const SizedBox(height: 8),
            Text(l10n.videoRequestLastFrame,
                style: Theme.of(context).textTheme.labelLarge),
            RadioGroup<String>(
              groupValue:
                  _lastFrame == null ? null : _candidateKey(_lastFrame!),
              onChanged: (key) {
                if (key == null) return;
                final candidate = _candidateForKey(key);
                if (candidate != null) setState(() => _lastFrame = candidate);
              },
              child: Column(
                children: [
                  for (final candidate in _imageCandidates
                      .where((item) => !_isFixedFirstFrame(item)))
                    RadioListTile<String>(
                      key: ValueKey(
                          'video-request-reference-${candidate.source.sourceType}-${candidate.source.sourceId}'),
                      contentPadding: EdgeInsets.zero,
                      value: _candidateKey(candidate),
                      title: Text(candidate.label),
                    ),
                ],
              ),
            ),
          ],
        );
      case VideoMode.multiReference:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.videoRequestReferences,
                style: Theme.of(context).textTheme.labelLarge),
            _candidateGroup(
              context,
              l10n.videoRequestStoryboardImages,
              widget.candidates.where((candidate) =>
                  candidate.source.sourceType == 'storyboard' &&
                  candidate.source.mediaType == 'image'),
            ),
            _candidateGroup(
              context,
              l10n.videoRequestAssetImages,
              widget.candidates.where((candidate) =>
                  candidate.source.sourceType == 'asset' &&
                  candidate.source.mediaType == 'image'),
            ),
            _candidateGroup(
              context,
              l10n.videoRequestReferenceVideos,
              widget.candidates
                  .where((candidate) => candidate.source.mediaType == 'video'),
            ),
            _candidateGroup(
              context,
              l10n.videoRequestReferenceAudio,
              widget.candidates
                  .where((candidate) => candidate.source.mediaType == 'audio'),
            ),
          ],
        );
    }
  }

  Widget _fixedFrameTile(String title) {
    final source = _fixedFirstFrame;
    final candidate = source == null
        ? null
        : widget.candidates
            .where((item) =>
                item.source.sourceType == source.sourceType &&
                item.source.sourceId == source.sourceId)
            .firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.image_outlined),
      title: Text(title),
      subtitle: Text(candidate?.label ?? '—'),
    );
  }

  Widget _multiReferenceTile(VideoReferenceCandidate candidate) {
    final key = _candidateKey(candidate);
    final selected = _multiReferenceKeys.contains(key);
    final limit =
        widget.capabilities.referenceLimits[candidate.source.mediaType] ?? 0;
    final selectedForType = _multiReferenceKeys
        .map(_candidateForKey)
        .whereType<VideoReferenceCandidate>()
        .where((item) => item.source.mediaType == candidate.source.mediaType)
        .length;
    final canSelect = selected || (limit > 0 && selectedForType < limit);
    return CheckboxListTile(
      key: ValueKey(
          'video-request-reference-${candidate.source.sourceType}-${candidate.source.sourceId}'),
      contentPadding: EdgeInsets.zero,
      value: selected,
      title: Text(candidate.label),
      onChanged: canSelect
          ? (value) => setState(() {
                if (value == true) {
                  _multiReferenceKeys.add(key);
                } else {
                  _multiReferenceKeys.remove(key);
                }
              })
          : null,
    );
  }

  Widget _candidateGroup(
    BuildContext context,
    String label,
    Iterable<VideoReferenceCandidate> candidates,
  ) {
    final items = candidates.toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        for (final candidate in items) _multiReferenceTile(candidate),
      ],
    );
  }

  VideoRequestDraft _result() => VideoRequestDraft(
        version: widget.initial.version,
        mode: _mode,
        references: switch (_mode) {
          VideoMode.text => const [],
          VideoMode.firstFrame => [
              if (_fixedFirstFrame case final source?) source,
            ],
          VideoMode.firstLastFrame => [
              if (_fixedFirstFrame case final source?) source,
              if (_lastFrame case final candidate?)
                _withRole(candidate.source, 'last_frame'),
            ],
          VideoMode.multiReference => [
              for (final key in _multiReferenceKeys)
                if (_candidateForKey(key) case final candidate?)
                  _withRole(
                    candidate.source,
                    _referenceRole(candidate.source.mediaType),
                  ),
            ],
        },
        duration: _duration,
        resolution: _resolution,
        ratio: _ratio,
        generateAudio:
            widget.capabilities.audio == 'required' ? true : _generateAudio,
      );

  VideoReferenceCandidate? _candidateForKey(String key) {
    for (final candidate in widget.candidates) {
      if (_candidateKey(candidate) == key) return candidate;
    }
    return null;
  }

  bool _isFixedFirstFrame(VideoReferenceCandidate candidate) {
    final fixed = _fixedFirstFrame;
    return fixed != null &&
        candidate.source.sourceType == fixed.sourceType &&
        candidate.source.sourceId == fixed.sourceId;
  }
}

Widget _choiceField<T>({
  required Key key,
  required String label,
  required T value,
  required List<T> options,
  required String Function(T value) labelFor,
  required ValueChanged<T> onChanged,
}) =>
    DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(labelFor(option))),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );

String _candidateKey(VideoReferenceCandidate candidate) =>
    '${candidate.source.sourceType}:${candidate.source.sourceId}';

String _referenceRole(String mediaType) => switch (mediaType) {
      'video' => 'reference_video',
      'audio' => 'reference_audio',
      _ => 'reference_image',
    };

VideoReferenceSource _withRole(VideoReferenceSource source, String role) =>
    VideoReferenceSource(
      sourceType: source.sourceType,
      sourceId: source.sourceId,
      mediaType: source.mediaType,
      role: role,
    );
