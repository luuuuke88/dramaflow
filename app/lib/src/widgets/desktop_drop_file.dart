import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';

String droppedFileName(DropItem file) {
  final name = file.name.trim();
  if (name.isNotEmpty) return name;
  final path = file.path.replaceAll('\\', '/');
  final slash = path.lastIndexOf('/');
  final fallback = slash < 0 ? path : path.substring(slash + 1);
  return fallback.isEmpty ? 'file' : fallback;
}

Future<Uint8List> readDroppedFileBytes(DropItem file) async {
  final bookmark = file.extraAppleBookmark;
  final needsScopedAccess =
      Platform.isMacOS && bookmark != null && bookmark.isNotEmpty;
  var accessStarted = false;
  if (needsScopedAccess) {
    accessStarted = await DesktopDrop.instance
        .startAccessingSecurityScopedResource(bookmark: bookmark);
  }
  try {
    return await file.readAsBytes();
  } finally {
    if (accessStarted) {
      try {
        await DesktopDrop.instance
            .stopAccessingSecurityScopedResource(bookmark: bookmark!);
      } catch (_) {
        // The byte read has already completed; a cleanup failure must not discard it.
      }
    }
  }
}
