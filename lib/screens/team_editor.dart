import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/player_widgets.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

/// Team composition belongs to registration, independently of later results.
class TournamentTeamEditor extends StatelessWidget {
  const TournamentTeamEditor({
    super.key,
    required this.store,
    required this.format,
    required this.teams,
    required this.onFormatChanged,
    required this.onTeamsChanged,
    required this.onTeamSizeChanged,
    required this.onMyTeamChanged,
    this.teamSize,
    this.myTeamId,
    this.enabled = true,
  });

  final GiriStore store;
  final TournamentFormat format;
  final List<GiriTeam> teams;
  final int? teamSize;
  final String? myTeamId;
  final ValueChanged<TournamentFormat> onFormatChanged;
  final ValueChanged<List<GiriTeam>> onTeamsChanged;
  final ValueChanged<int?> onTeamSizeChanged;
  final ValueChanged<String?> onMyTeamChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StairFormSection(
        title: '大会の形式',
        icon: CupertinoIcons.person_2,
        accent: StairColors.online,
        children: [
          StairMenuRow<TournamentFormat>(
            key: const ValueKey('event-tournament-format'),
            label: '参加形式',
            value: format,
            items: {
              TournamentFormat.individual: '個人戦',
              TournamentFormat.team: 'チーム戦',
              if (format == TournamentFormat.pair)
                TournamentFormat.pair: 'タッグ戦',
            },
            onChanged: enabled ? onFormatChanged : null,
          ),
          if (format != TournamentFormat.individual) ...[
            StairMenuRow<int>(
              label: 'チーム人数',
              value: teamSize ?? 0,
              items: {
                0: '制限なし',
                for (var size = 2; size <= 6; size++) size: '$size人',
                if (teamSize != null && teamSize! > 6)
                  teamSize!: '$teamSize人',
              },
              onChanged: enabled
                  ? (size) => onTeamSizeChanged(size == 0 ? null : size)
                  : null,
            ),
            StairMenuRow<String>(
              label: '自分のチーム',
              value: teams.any((team) => team.id == myTeamId)
                  ? myTeamId!
                  : '__none__',
              items: {
                '__none__': '未設定',
                for (var i = 0; i < teams.length; i++)
                  teams[i].id: teams[i].name.trim().isEmpty
                      ? 'チーム${i + 1}'
                      : teams[i].name,
              },
              onChanged: enabled
                  ? (id) => onMyTeamChanged(id == '__none__' ? null : id)
                  : null,
            ),
          ],
        ],
      ),
      if (format != TournamentFormat.individual) ...[
        for (var index = 0; index < teams.length; index++)
          _TeamFields(
            key: ValueKey(teams[index].id),
            store: store,
            team: teams[index],
            title: teams[index].id == myTeamId
                ? '自分のチーム'
                : 'チーム${index + 1}',
            enabled: enabled,
            teamSize: teamSize,
            onChanged: (team) {
              final changed = List<GiriTeam>.of(teams);
              changed[index] = team;
              onTeamsChanged(changed);
            },
            onRemove: () {
              onTeamsChanged(List.of(teams)..removeAt(index));
              if (teams[index].id == myTeamId) onMyTeamChanged(null);
            },
          ),
        OutlinedButton.icon(
          key: const ValueKey('event-team-add'),
          onPressed: enabled
              ? () {
                  final id = store.newId();
                  final mine = teams.isEmpty;
                  onTeamsChanged([
                    ...teams,
                    GiriTeam(
                      id: id,
                      isMine: mine,
                      members: mine && store.preferences.selfName.isNotEmpty
                          ? [store.preferences.selfName]
                          : const [],
                    ),
                  ]);
                  if (mine) onMyTeamChanged(id);
                }
              : null,
          icon: const Icon(CupertinoIcons.plus_circle, size: 20),
          label: const Text('チームを追加'),
        ),
        const SizedBox(height: 14),
      ],
    ],
  );
}

class _TeamFields extends StatefulWidget {
  const _TeamFields({
    super.key,
    required this.store,
    required this.team,
    required this.title,
    required this.onChanged,
    required this.onRemove,
    required this.enabled,
    this.teamSize,
  });
  final GiriStore store;
  final GiriTeam team;
  final String title;
  final ValueChanged<GiriTeam> onChanged;
  final VoidCallback onRemove;
  final bool enabled;
  final int? teamSize;

  @override
  State<_TeamFields> createState() => _TeamFieldsState();
}

class _TeamFieldsState extends State<_TeamFields> {
  late final _name = TextEditingController(text: widget.team.name);
  late final _members = (widget.team.members.isEmpty
          ? const ['']
          : widget.team.members)
      .map((name) => TextEditingController(text: name))
      .toList();

  @override
  void dispose() {
    _name.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  void _changed() => widget.onChanged(
    widget.team.copyWith(
      name: _name.text,
      members: _members
          .map((member) => member.text.trim())
          .where((name) => name.isNotEmpty)
          .toList(),
    ),
  );

  @override
  Widget build(BuildContext context) => StairFormSection(
    title: widget.title,
    icon: CupertinoIcons.person_2,
    accent: StairColors.online,
    trailing: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: widget.enabled ? widget.onRemove : null,
      child: const Icon(CupertinoIcons.minus_circle, size: 20),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextFormField(
          key: ValueKey('team-name-${widget.team.id}'),
          controller: _name,
          enabled: widget.enabled,
          style: StairTypography.role(StairTextRole.input),
          decoration: const InputDecoration(hintText: 'チーム名'),
          onChanged: (_) => _changed(),
        ),
      ),
      for (var index = 0; index < _members.length; index++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: PlayerSuggestionField(
                  key: ValueKey('team-member-${widget.team.id}-$index'),
                  store: widget.store,
                  controller: _members[index],
                  compact: true,
                  enabled: widget.enabled,
                  hint: 'メンバー名',
                  onChanged: (_) => _changed(),
                  onSelected: (_) => _changed(),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 44),
                onPressed: widget.enabled
                    ? () {
                        setState(() {
                          _members.removeAt(index).dispose();
                          if (_members.isEmpty) {
                            _members.add(TextEditingController());
                          }
                        });
                        _changed();
                      }
                    : null,
                child: const Icon(CupertinoIcons.minus_circle, size: 20),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: TextButton.icon(
          onPressed: !widget.enabled ||
                  (widget.teamSize != null &&
                      _members.length >= widget.teamSize!)
              ? null
              : () => setState(() => _members.add(TextEditingController())),
          icon: const Icon(CupertinoIcons.plus_circle, size: 18),
          label: const Text('メンバーを追加'),
        ),
      ),
    ],
  );
}
