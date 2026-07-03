import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 项目列表（App 首页）。
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: FilledButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('新建项目'),
            ),
          ),
        ],
      ),
      body: PageContainer(
        child: AsyncView<List<Project>>(
          value: projects,
          onRetry: () => ref.invalidate(projectsProvider),
          builder: (list) {
            if (list.isEmpty) {
              return EmptyHint(
                icon: Icons.movie_outlined,
                title: '还没有项目',
                subtitle: '创建一个项目，从导入小说开始你的短剧流水线',
                action: FilledButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('新建项目'),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.symmetric(vertical: 20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.5,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) => _ProjectCard(project: list[i]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final styleCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建项目'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '项目名称',
                    hintText: '如：龙王赘婿',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入项目名称' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: styleCtrl,
                  decoration: const InputDecoration(
                    labelText: '画风',
                    hintText: '如：国风动漫，厚涂插画风。可留空',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = nameCtrl.text.trim();
    final artStyle = styleCtrl.text.trim();
    if (!context.mounted) return;

    Project? created;
    await runAction(
      context,
      ref,
      () async {
        created = await ref
            .read(engineProvider)
            .createProject(name, artStyle: artStyle);
      },
      successMessage: '项目已创建',
    );
    if (created == null || !context.mounted) return;
    ref.invalidate(projectsProvider);
    context.go('/projects/${created!.id}');
  }
}

class _ProjectCard extends ConsumerWidget {
  final Project project;

  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = project.stats;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/projects/${project.id}'),
        hoverColor: context.df.cardHover,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        project.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: context.df.textLo, size: 20),
                    color: context.df.card,
                    onSelected: (v) {
                      if (v == 'delete') _confirmDelete(context, ref);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: context.df.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: context.df.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (project.artStyle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.df.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: context.df.primary.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    project.artStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.df.primary),
                  ),
                ),
              ],
              const Spacer(),
              _StatLine(
                icon: Icons.menu_book_outlined,
                label: '小说',
                value: s.hasNovel ? '✓' : '—',
                done: s.hasNovel,
              ),
              const SizedBox(height: 4),
              _StatLine(
                icon: Icons.description_outlined,
                label: '剧本',
                value: '${s.episodes} 集',
                done: s.episodes > 0,
              ),
              const SizedBox(height: 4),
              _StatLine(
                icon: Icons.palette_outlined,
                label: '素材',
                value: '${s.assetsDone}/${s.assets}',
                done: s.assets > 0 && s.assetsDone == s.assets,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _StatLine(
                      icon: Icons.image_outlined,
                      label: '镜头图',
                      value: '${s.shotsImageDone}/${s.shots}',
                      done: s.shots > 0 && s.shotsImageDone == s.shots,
                    ),
                  ),
                  Expanded(
                    child: _StatLine(
                      icon: Icons.videocam_outlined,
                      label: '视频',
                      value: '${s.shotsVideoDone}/${s.shots}',
                      done: s.shots > 0 && s.shotsVideoDone == s.shots,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确定删除「${project.name}」吗？\n项目下的小说、剧本、素材与镜头都会一并删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: context.df.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await runAction(
      context,
      ref,
      () => ref.read(engineProvider).deleteProject(project.id),
      successMessage: '项目已删除',
    );
    if (!context.mounted) return;
    ref.invalidate(projectsProvider);
  }
}

class _StatLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool done;

  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 14, color: done ? context.df.green : context.df.textLo),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: context.df.textLo)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: done ? context.df.green : context.df.textMid,
            ),
          ),
        ),
      ],
    );
  }
}
