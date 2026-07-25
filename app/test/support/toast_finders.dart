import 'package:dramaflow/src/widgets/df_toast.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在当前提示条里找指定文案。
///
/// 全应用的反馈已从底部 SnackBar 换成顶部提示条，测试统一走这个入口，
/// 不再依赖 SnackBar 这个具体控件类型。
Finder findDFToastWithText(String text) => find.descendant(
      of: find.byKey(dfToastKey),
      matching: find.text(text),
    );
