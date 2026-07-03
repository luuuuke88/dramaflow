// 配音页（照抄 cornerScape/index.vue 语义，见 P4 参照 §4）：角色资产列表 + 音频绑定
// （手动下拉选择 / AI 自动匹配批量）。语音合成不做——音频素材来自素材中心的音频资产上传，
// 本页只做"绑定关系"。
//
// 列表管理控件（对齐 ToonFlow cornerScape 列表上方的筛选/快捷选择区）：
//   - 绑定状态筛选（全部 / 已绑定 / 未绑定）过滤可见列表；
//   - 角色名称搜索（复用 DFSearchField）；
//   - 「全选未绑定」快捷动作，把当前可见未绑定角色喂给既有的批量 AI 匹配选择。
// 说明：ToonFlow 的 cornerScape 列表按资产类型（角色/场景/道具）筛选并展示参考图轮播；
// 但本页的数据源 engine.roleAudioBindings() 只返回角色类资产，且不携带图片字段
// （roleId/roleName/audioAssetId/audioName），故资产类型筛选与批量图片预览在本页数据上
// 无对应意义，未实现——改为实现对真实数据有效的"绑定状态"筛选。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/audio_bind.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_search_field.dart';

enum _BindFilter { all, bound, unbound }

class CornerScapeScreen extends ConsumerStatefulWidget {
  final int projectId;
  const CornerScapeScreen({super.key, required this.projectId});

  @override
  ConsumerState<CornerScapeScreen> createState() => _CornerScapeScreenState();
}

class _CornerScapeScreenState extends ConsumerState<CornerScapeScreen> {
  final Set<int> _selected = {};
  _BindFilter _filter = _BindFilter.all;
  String _query = '';

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _matchesFilter(RoleAudioBinding r) {
    switch (_filter) {
      case _BindFilter.all:
        return true;
      case _BindFilter.bound:
        return r.audioAssetId != null;
      case _BindFilter.unbound:
        return r.audioAssetId == null;
    }
  }

  bool _matchesQuery(RoleAudioBinding r) {
    if (_query.isEmpty) return true;
    return (r.roleName ?? '').toLowerCase().contains(_query.toLowerCase());
  }

  List<RoleAudioBinding> _visible(List<RoleAudioBinding> roles) =>
      roles.where((r) => _matchesFilter(r) && _matchesQuery(r)).toList();

  void _autoMatch(List<({int id, String name})> pool) {
    final l10n = context.l10n;
    if (pool.isEmpty) {
      _toast(l10n.cornerScapeNoAudioPool);
      return;
    }
    if (_selected.isEmpty) {
      _toast(l10n.cornerScapeSelectAtLeastOne);
      return;
    }
    ref
        .read(engineProvider)
        .batchBindAudio(widget.projectId, _selected.toList());
    _toast(l10n.cornerScapeAutoMatching);
  }

  /// 把当前可见的未绑定角色加入批量 AI 匹配选择集。
  void _selectAllUnbound(List<RoleAudioBinding> visible) {
    setState(() {
      for (final r in visible) {
        if (r.audioAssetId == null) _selected.add(r.roleId);
      }
    });
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

    // 剔除已不存在的角色选择（防御：角色被删除后残留脏选择）。
    final roleIds = roles.map((r) => r.roleId).toSet();
    _selected.removeWhere((id) => !roleIds.contains(id));

    final visible = _visible(roles);
    final boundCount = roles.where((r) => r.audioAssetId != null).length;
    final visibleUnboundCount =
        visible.where((r) => r.audioAssetId == null).length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          Text(l10n.cornerScapeTitle,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Text(
            l10n.cornerScapeBoundSummary(boundCount, roles.length),
            style: TextStyle(fontSize: 12, color: df.textTertiary),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _autoMatch(pool),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(_selected.isEmpty
                ? l10n.cornerScapeAutoMatch
                : '${l10n.cornerScapeAutoMatch} (${_selected.length})'),
          ),
        ]),
      ),
      // 列表管理工具栏：状态筛选 + 搜索 + 全选未绑定。用 Wrap 保证窄屏（移动端）换行。
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_BindFilter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: _BindFilter.all,
                    label: Text(l10n.cornerScapeFilterAll)),
                ButtonSegment(
                    value: _BindFilter.bound,
                    label: Text(l10n.cornerScapeFilterBound)),
                ButtonSegment(
                    value: _BindFilter.unbound,
                    label: Text(l10n.cornerScapeFilterUnbound)),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
            DFSearchField(
              width: 220,
              hint: l10n.cornerScapeSearchHint,
              onSearch: (v) => setState(() => _query = v.trim()),
            ),
            OutlinedButton.icon(
              onPressed: visibleUnboundCount == 0
                  ? null
                  : () => _selectAllUnbound(visible),
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: Text(l10n.cornerScapeSelectAllUnbound),
            ),
          ],
        ),
      ),
      if (pool.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(l10n.cornerScapeNoAudioPool,
              style: TextStyle(fontSize: 12, color: df.warning)),
        ),
      Expanded(
        child: visible.isEmpty
            ? Center(child: DFEmpty(text: l10n.cornerScapeNoMatch))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: visible.length,
                separatorBuilder: (c, i) => const SizedBox(height: 8),
                itemBuilder: (c, i) {
                  final role = visible[i];
                  final selected = _selected.contains(role.roleId);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: df.surface,
                      borderRadius: BorderRadius.circular(DFTokens.radiusCard),
                      border:
                          Border.all(color: selected ? df.primary : df.stroke),
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
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int?>(
                          initialValue: role.audioAssetId,
                          isExpanded: true,
                          hint: Text(l10n.cornerScapeNoAudio,
                              style: TextStyle(
                                  fontSize: 12, color: df.textTertiary)),
                          items: [
                            DropdownMenuItem(
                                value: null,
                                child: Text(l10n.cornerScapeUnbind,
                                    style: const TextStyle(fontSize: 12))),
                            for (final a in pool)
                              DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.name,
                                      style: const TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) {
                            try {
                              ref
                                  .read(engineProvider)
                                  .bindRoleAudio(role.roleId, v);
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
