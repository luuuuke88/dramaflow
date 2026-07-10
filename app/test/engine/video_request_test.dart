import 'dart:io';

import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/video_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final firstFrameOnly = const VideoReference(
    mediaType: 'image',
    role: 'first_frame',
    localPath: 'p/first.png',
  );
  final fourImageReferences = [
    for (var i = 0; i < 4; i++)
      VideoReference(
        mediaType: 'image',
        role: 'reference_image',
        localPath: 'p/$i.png',
      ),
  ];

  VideoGenerationRequest requestFor({
    required VideoMode mode,
    required List<VideoReference> references,
  }) =>
      VideoGenerationRequest(
        modelBinding: 'volcengine:test-video',
        mode: mode,
        prompt: 'PROMPT',
        references: references,
        duration: 4,
        resolution: '720p',
        ratio: '16:9',
        generateAudio: false,
        projectId: 1,
        storyboardId: 2,
        videoTrackId: 3,
      );

  test('parses declared capabilities and rejects invalid local requests', () {
    final caps = VideoModelCapabilities.fromJson({
      'video': {
        'modes': ['text', 'first_frame', 'first_last_frame', 'multi_reference'],
        'references': {'image': 3, 'video': 1, 'audio': 1},
        'durations': [4, 5],
        'resolutions': ['480p', '720p'],
        'ratios': ['16:9', '9:16'],
        'audio': 'optional',
      },
    });

    expect(caps.supports(VideoMode.multiReference), isTrue);
    expect(
      () => caps.validate(
        requestFor(
          mode: VideoMode.firstLastFrame,
          references: [firstFrameOnly],
        ),
      ),
      throwsA(
        isA<EngineException>().having((e) => e.errKey, 'errKey', errLlmFormat),
      ),
    );
    expect(
      () => caps.validate(
        requestFor(
          mode: VideoMode.text,
          references: [firstFrameOnly],
        ),
      ),
      throwsA(
        isA<EngineException>().having((e) => e.errKey, 'errKey', errLlmFormat),
      ),
    );
    expect(
      () => caps.validate(
        requestFor(
          mode: VideoMode.multiReference,
          references: fourImageReferences,
        ),
      ),
      throwsA(
        isA<EngineException>().having((e) => e.errKey, 'errKey', errLlmFormat),
      ),
    );
    expect(
      () => caps.validate(
        requestFor(
          mode: VideoMode.multiReference,
          references: const [
            VideoReference(
              mediaType: 'image',
              role: 'reference_image',
              localPath: '/tmp/absolute.png',
            ),
          ],
        ),
      ),
      throwsA(
        isA<EngineException>().having((e) => e.errKey, 'errKey', errLlmFormat),
      ),
    );

    expect(
      () => caps.validate(
        requestFor(
          mode: VideoMode.firstFrame,
          references: [firstFrameOnly],
        ),
      ),
      returnsNormally,
    );
  });

  test(
      'legacy first-frame compatibility keeps old duration and resolution data',
      () {
    final caps = VideoModelCapabilities.fromJson(
      {
        'durations': [4, 5],
        'resolutions': ['480p', '720p'],
      },
      legacyFirstFrame: true,
    );

    expect(caps.modes, {VideoMode.firstFrame});
    expect(caps.durations, {4, 5});
    expect(caps.resolutions, {'480p', '720p'});
    expect(caps.ratios, {'16:9', '9:16'});
    expect(caps.audio, 'none');
    expect(caps.supports(VideoMode.multiReference), isFalse);
  });

  test(
      'fingerprints change with output-affecting inputs and ignore absolute media roots',
      () {
    final tempDirectory =
        Directory.systemTemp.createTempSync('dramaflow-video-request-');
    addTearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    final request = requestFor(
      mode: VideoMode.firstFrame,
      references: [firstFrameOnly],
    );
    final differentPrompt = VideoGenerationRequest(
      modelBinding: request.modelBinding,
      mode: request.mode,
      prompt: 'OTHER',
      references: request.references,
      duration: request.duration,
      resolution: request.resolution,
      ratio: request.ratio,
      generateAudio: request.generateAudio,
      projectId: request.projectId,
      storyboardId: request.storyboardId,
      videoTrackId: request.videoTrackId,
    );
    final sameOutputDifferentContext = VideoGenerationRequest(
      modelBinding: request.modelBinding,
      mode: request.mode,
      prompt: request.prompt,
      references: request.references,
      duration: request.duration,
      resolution: request.resolution,
      ratio: request.ratio,
      generateAudio: request.generateAudio,
      projectId: 99,
      storyboardId: 98,
      videoTrackId: 97,
    );

    expect(
      request.copyWith(duration: 5).fingerprint(),
      isNot(request.copyWith(duration: 4).fingerprint()),
    );
    expect(differentPrompt.fingerprint(), isNot(request.fingerprint()));
    expect(
      sameOutputDifferentContext.fingerprint(),
      request.fingerprint(),
    );
    expect(request.fingerprintMaterial(), isNot(contains(tempDirectory.path)));
  });
}
