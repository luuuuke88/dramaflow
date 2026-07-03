import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/df_page_scaffold.dart';

// T9 全量重写
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final projects = ref.watch(projectsProvider);
    return DFPageScaffold(
      title: l10n.projectListTitle,
      subtitle: l10n.projectListSubtitle,
      toolbar: FilledButton.icon(
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(l10n.projectNew),
        onPressed: () => _createProject(context, ref),
      ),
      body: AsyncView(
        value: projects,
        onRetry: () => ref.invalidate(projectsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                l10n.projectEmpty,
                style: TextStyle(color: context.df.textSecondary),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final project = items[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.movie_creation_outlined),
                  title: Text(project.name?.isNotEmpty == true
                      ? project.name!
                      : l10n.projectUntitled),
                  subtitle: Text('#${project.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.projectNew),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.projectName),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.projectCreate),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    await runAction(context, ref, () async {
      ref.read(engineProvider).addProject(
            projectType: 'drama',
            name: name,
          );
      ref.invalidate(projectsProvider);
    }, successMessage: l10n.projectCreated);
  }
}
