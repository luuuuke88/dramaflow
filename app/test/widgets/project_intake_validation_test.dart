import 'package:dramaflow/src/screens/project/project_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProjectIntakeField? validate({
    String name = '项目',
    String type = '玄幻',
    String imageModel = 'image-provider:image-model',
    String videoModel = 'video-provider:video-model',
    String artStyle = 'visual_pack',
    String directorManual = 'director_pack',
    String videoRatio = '16:9',
    String intro = '项目简介',
    String imageQuality = '1K',
    String mode = 'first_frame',
  }) =>
      firstMissingProjectIntakeField(
        name: name,
        type: type,
        imageModel: imageModel,
        videoModel: videoModel,
        artStyle: artStyle,
        directorManual: directorManual,
        videoRatio: videoRatio,
        intro: intro,
        imageQuality: imageQuality,
        mode: mode,
      );

  test('项目向导按 ToonFlow 的十项顺序返回首个缺失字段', () {
    expect(validate(name: ''), ProjectIntakeField.name);
    expect(validate(type: ''), ProjectIntakeField.type);
    expect(validate(imageModel: ''), ProjectIntakeField.imageModel);
    expect(validate(videoModel: ''), ProjectIntakeField.videoModel);
    expect(validate(artStyle: ''), ProjectIntakeField.artStyle);
    expect(validate(directorManual: ''), ProjectIntakeField.directorManual);
    expect(validate(videoRatio: ''), ProjectIntakeField.videoRatio);
    expect(validate(intro: ''), ProjectIntakeField.intro);
    expect(validate(imageQuality: ''), ProjectIntakeField.imageQuality);
    expect(validate(mode: ''), ProjectIntakeField.mode);
    expect(validate(), isNull);
  });
}
