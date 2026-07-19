import 'package:dramaflow/src/screens/production/workbench_preview_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放跨越镜头、末镜停止并可从结尾重新播放', () {
    final controller = PreviewTimelineController(const [
      Duration(seconds: 2),
      Duration(seconds: 3),
    ]);
    addTearDown(controller.dispose);

    controller.togglePlay();
    controller.tick(const Duration(milliseconds: 2500));
    expect(controller.currentIndex, 1);
    expect(controller.elapsed, const Duration(milliseconds: 500));
    expect(controller.totalElapsed, const Duration(milliseconds: 2500));

    controller.tick(const Duration(seconds: 3));
    expect(controller.isPlaying, isFalse);
    expect(controller.currentIndex, 1);
    expect(controller.elapsed, const Duration(seconds: 3));
    expect(controller.progress, 1);

    controller.togglePlay();
    expect(controller.isPlaying, isTrue);
    expect(controller.currentIndex, 0);
    expect(controller.elapsed, Duration.zero);
  });

  test('定位会夹紧总时长并在镜头边界落到下一镜', () {
    final controller = PreviewTimelineController(const [
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 4),
    ]);
    addTearDown(controller.dispose);

    controller.seek(const Duration(seconds: 2));
    expect(controller.currentIndex, 1);
    expect(controller.elapsed, Duration.zero);

    controller.seek(const Duration(seconds: 99));
    expect(controller.currentIndex, 2);
    expect(controller.elapsed, const Duration(seconds: 4));

    controller.seek(const Duration(seconds: -1));
    expect(controller.currentIndex, 0);
    expect(controller.elapsed, Duration.zero);
  });

  test('空分镜不播放且跳镜不会越界', () {
    final controller = PreviewTimelineController(const []);
    addTearDown(controller.dispose);

    controller.togglePlay();
    controller.tick(const Duration(seconds: 1));
    controller.next();
    controller.previous();
    controller.seek(const Duration(seconds: 1));

    expect(controller.isPlaying, isFalse);
    expect(controller.currentIndex, 0);
    expect(controller.totalDuration, Duration.zero);
    expect(controller.progress, 0);
  });
}
