import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 小说页：导入 / 编辑项目原著文本（覆盖式保存）。
class NovelScreen extends ConsumerStatefulWidget {
  final String projectId;

  const NovelScreen({super.key, required this.projectId});

  @override
  ConsumerState<NovelScreen> createState() => _NovelScreenState();
}

class _NovelScreenState extends ConsumerState<NovelScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  /// 只用后端数据初始化一次，之后保留本地编辑（后台刷新不覆盖）。
  bool _initialized = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await runAction(context, ref, () async {
      await ref.read(apiProvider).saveNovel(
            widget.projectId,
            title: _titleCtrl.text.trim(),
            content: _contentCtrl.text,
          );
      ref.invalidate(novelProvider(widget.projectId));
      ref.invalidate(projectProvider(widget.projectId));
    }, successMessage: '已保存');
  }

  @override
  Widget build(BuildContext context) {
    final novelAsync = ref.watch(novelProvider(widget.projectId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回项目',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/projects/${widget.projectId}'),
        ),
        title: const Text('小说'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: AsyncView<Novel?>(
        value: novelAsync,
        onRetry: () => ref.invalidate(novelProvider(widget.projectId)),
        builder: (novel) {
          if (!_initialized) {
            _initialized = true;
            _titleCtrl.text = novel?.title ?? '';
            _contentCtrl.text = novel?.content ?? '';
          }
          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return PageContainer(
              maxWidth: wide ? 840 : 1200,
              child: _buildEditor(context),
            );
          });
        },
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: '书名',
            prefixIcon: Icon(Icons.menu_book_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TextField(
            controller: _contentCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['Menlo', 'Consolas', 'PingFang SC'],
              fontSize: 14,
              height: 1.8,
              color: DF.textHi,
            ),
            decoration: const InputDecoration(
              hintText: '粘贴小说正文……',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '共 ${_contentCtrl.text.length} 字',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: DF.textLo),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
