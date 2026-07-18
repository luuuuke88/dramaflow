import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../theme/tokens.dart';
import '../util/l10n_ext.dart';
import 'asset_image_preview.dart';

enum LocalMediaKind { image, video, audio, unknown }

LocalMediaKind localMediaKind(String? path) {
  final extension = path?.split('?').first.split('.').last.toLowerCase() ?? '';
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'}
      .contains(extension)) {
    return LocalMediaKind.image;
  }
  if (const {'mp4', 'webm', 'ogg', 'mov', 'avi', 'mkv'}.contains(extension)) {
    return LocalMediaKind.video;
  }
  if (const {'mp3', 'wav', 'm4a', 'aac', 'flac', 'aiff'}.contains(extension)) {
    return LocalMediaKind.audio;
  }
  return LocalMediaKind.unknown;
}

bool _mediaKitReady = false;

void ensureLocalMediaKit() {
  if (_mediaKitReady) return;
  MediaKit.ensureInitialized();
  _mediaKitReady = true;
}

Future<void> showLocalMediaPreview(
  BuildContext context, {
  required String absPath,
  required LocalMediaKind kind,
  String? title,
}) {
  if (kind == LocalMediaKind.image) {
    return showAssetImagePreview(context, absPath: absPath);
  }
  if (kind == LocalMediaKind.unknown) return Future.value();
  final mobile = MediaQuery.sizeOf(context).width < 840;
  if (mobile) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          key: const Key('asset-media-preview'),
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(kind == LocalMediaKind.audio
                ? context.l10n.assetsPlay
                : context.l10n.workbenchPlayVideo),
          ),
          body: SafeArea(
              child: _LocalMediaPlayerSurface(
                  absPath: absPath, kind: kind, title: title, expand: true)),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (_) => Dialog(
      key: const Key('asset-media-preview'),
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(DFTokens.s24),
      child: _LocalMediaPlayerSurface(
          absPath: absPath, kind: kind, title: title, showCloseButton: true),
    ),
  );
}

class _LocalMediaPlayerSurface extends StatefulWidget {
  final String absPath;
  final LocalMediaKind kind;
  final String? title;
  final bool expand;
  final bool showCloseButton;

  const _LocalMediaPlayerSurface({
    required this.absPath,
    required this.kind,
    this.title,
    this.expand = false,
    this.showCloseButton = false,
  });

  @override
  State<_LocalMediaPlayerSurface> createState() =>
      _LocalMediaPlayerSurfaceState();
}

class _LocalMediaPlayerSurfaceState extends State<_LocalMediaPlayerSurface> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<String>? _errorSub;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    try {
      if (!File(widget.absPath).existsSync()) {
        _errored = true;
        return;
      }
      ensureLocalMediaKit();
      final player = Player();
      _player = player;
      if (widget.kind == LocalMediaKind.video) {
        _controller = VideoController(player);
      }
      _errorSub = player.stream.error.listen((_) {
        if (mounted) setState(() => _errored = true);
      });
      player.open(Media(widget.absPath), play: true);
    } catch (_) {
      _errored = true;
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_errored || _player == null) {
      content = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.kind == LocalMediaKind.audio &&
              (widget.title?.trim().isNotEmpty ?? false)) ...[
            Text(
              widget.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 12),
          ],
          Text(context.l10n.workbenchVideoLoadFailed,
              style: const TextStyle(color: Colors.white70)),
        ]),
      );
    } else if (widget.kind == LocalMediaKind.audio) {
      content = _audioSurface(_player!);
    } else {
      final controller = _controller;
      content = AspectRatio(
        aspectRatio: 16 / 9,
        child: controller == null
            ? Center(
                child: Text(context.l10n.workbenchVideoLoadFailed,
                    style: const TextStyle(color: Colors.white70)),
              )
            : Video(controller: controller),
      );
    }
    return Stack(
      key: widget.kind == LocalMediaKind.video
          ? const ValueKey('workbench-video-player-screen')
          : const ValueKey('asset-audio-player-screen'),
      children: [
        widget.expand ? Center(child: content) : content,
        if (widget.showCloseButton)
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: context.l10n.commonClose,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _audioSurface(Player player) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: false,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? false;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.music_note_rounded,
                  color: Colors.white, size: 64),
              if (widget.title?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                Text(
                  widget.title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
              const SizedBox(height: 16),
              IconButton.filled(
                tooltip: context.l10n.assetsPlay,
                onPressed: () => playing ? player.pause() : player.play(),
                icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
