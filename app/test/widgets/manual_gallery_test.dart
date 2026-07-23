import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/screens/manuals/manual_gallery.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget themed(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      theme: buildTheme(Brightness.light),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );
  }

  final packs = [
    const ManualPack(name: '风格手册', pack: 'style-a', images: [], data: {}),
  ];

  testWidgets('有封面的手册卡片可打开封面大图预览', (tester) async {
    final fixtureDir = Directory.systemTemp.createTempSync('manual-gallery-');
    addTearDown(() => fixtureDir.deleteSync(recursive: true));
    final cover = File('${fixtureDir.path}/cover.png');
    cover.writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAF/gL+6fD6nwAAAABJRU5ErkJggg=='));

    await tester.pumpWidget(themed(ManualGallery(
      title: '视觉手册',
      addLabel: '新建手册',
      packs: [
        ManualPack(
            name: '国风画风',
            pack: 'style-covered',
            images: [cover.path],
            data: const {}),
      ],
      selectedPackId: null,
      onSelect: (_) {},
      onCreate: () {},
      onEdit: (_) {},
      onDelete: (_) {},
    )));
    await tester.pump();

    final preview = find.byIcon(Icons.zoom_in);
    expect(preview, findsOneWidget);
    await tester.tap(preview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 预览用的是可左右切换手册/查看多图的大卡片，而不是单图放大层：
    // 弹窗标题栏应展示当前手册名（画廊背后的卡片名条也有同名文本，需限定在弹窗内）。
    expect(
      find.descendant(
          of: find.byType(Dialog), matching: find.text('国风画风')),
      findsOneWidget,
    );
  });

  testWidgets('手机宽度下手册卡片的编辑/删除按钮无需悬停即可见并可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    ManualPack? edited;
    ManualPack? deleted;

    await tester.pumpWidget(themed(ManualGallery(
      title: '导演手册',
      addLabel: '新建手册',
      packs: packs,
      selectedPackId: null,
      onSelect: (_) {},
      onCreate: () {},
      onEdit: (p) => edited = p,
      onDelete: (p) => deleted = p,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 触屏设备不会触发 MouseRegion 的 hover，因此这里全程不模拟 hover，
    // 直接断言编辑/删除迷你图标已经可见（回归 L143-161 的悬停死角问题）。
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(edited?.pack, 'style-a');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(deleted?.pack, 'style-a');

  });

  testWidgets('移动壳平板宽度下手册卡片操作仍无需 hover', (tester) async {
    tester.view.physicalSize = const Size(800, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(themed(ManualGallery(
      title: '导演手册',
      addLabel: '新建手册',
      packs: packs,
      selectedPackId: null,
      onSelect: (_) {},
      onCreate: () {},
      onEdit: (_) {},
      onDelete: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
