// 配音页（照抄 cornerScape/index.vue 语义，见 P4 参照 §4）：角色资产列表 + 音频绑定
// （手动下拉选择 / AI 自动匹配批量）。语音合成不做——音频素材来自素材中心的音频资产上传，
// 本页只做"绑定关系"。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/audio_bind.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';

class CornerScapeScreen extends ConsumerStatefulWidget {
  final int projectId;
  const CornerScapeScreen({super.key, required this.projectId});

  @override
  ConsumerState<CornerScapeScreen> createState() => _CornerScapeScreenState();
}

class _CornerScapeScreenState extends ConsumerState<CornerScapeScreen> {
  final Set<int> _selected = {};

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _autoMatch(List<RoleAudioBinding> roles, List<({int id, String name})> pool) {
    final l10n = context.l10n;
    if (pool.isEmpty) {
      _toast(l10n.cornerScapeNoAudioPool);
      return;
    }
    if (_selected.isEmpty) {
      _toast(l10n.cornerScapeSelectAtLeastOne);
      return;
    }
    ref.read(engineProvider).batchBindAudio(widget.projectId, _selected.toList());
    _toast(l10n.cornerScapeAutoMatching);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final engine = ref.watch(engineProvider);
    final roles = engine.roleAudioBindings(widget.projectId);
    final pool = engine.audioPool(widget.projectId);

    if (roles.isEmpty) {
      return Center(child: DFEmpty(text: l10n.cornerScapeNoRoles));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          Text(l10n.cornerScapeTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _autoMatch(roles, pool),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(_selected.isEmpty
                ? l10n.cornerScapeAutoMatch
                : '${l10n.cornerScapeAutoMatch} (${_selected.length})'),
          ),
        ]),
      ),
      if (pool.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(l10n.cornerScapeNoAudioPool,
              style: TextStyle(fontSize: 12, color: df.warning)),
        ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: roles.length,
          separatorBuilder: (c, i) => const SizedBox(height: 8),
          itemBuilder: (c, i) {
            final role = roles[i];
            final selected = _selected.contains(role.roleId);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: df.surface,
                borderRadius: BorderRadius.circular(DFTokens.radiusCard),
                border: Border.all(color: selected ? df.primary : df.stroke),
              ),
              child: Row(children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(role.roleId);
                    } else {
                      _selected.remove(role.roleId);
                    }
                  }),
                ),
                Expanded(
                  child: Text(role.roleName ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int?>(
                    initialValue: role.audioAssetId,
                    isExpanded: true,
                    hint: Text(l10n.cornerScapeNoAudio,
                        style: TextStyle(fontSize: 12, color: df.textTertiary)),
                    items: [
                      DropdownMenuItem(
                          value: null,
                          child: Text(l10n.cornerScapeUnbind,
                              style: const TextStyle(fontSize: 12))),
                      for (final a in pool)
                        DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name, style: const TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) {
                      try {
                        ref.read(engineProvider).bindRoleAudio(role.roleId, v);
                      } catch (e) {
                        _toast(localizeError(context, e));
                      }
                    },
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
