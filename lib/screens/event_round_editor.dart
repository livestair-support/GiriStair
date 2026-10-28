import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'stage_name_row.dart';

class EventRoundEditor extends StatelessWidget {
  const EventRoundEditor({
    super.key,
    required this.rounds,
    required this.onChanged,
    required this.newId,
    this.enabled = true,
  });

  final List<EventRound> rounds;
  final ValueChanged<List<EventRound>> onChanged;
  final String Function() newId;
  final bool enabled;

  void _replace(int index, EventRound round) {
    final changed = List<EventRound>.of(rounds);
    changed[index] = round;
    onChanged(changed);
  }

  void _move(int index, int offset) {
    final changed = List<EventRound>.of(rounds);
    final item = changed.removeAt(index);
    changed.insert(index + offset, item);
    onChanged(changed);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < rounds.length; index++)
        StairFormSection(
          key: ValueKey('event-round-${rounds[index].id}'),
          title: rounds[index].name,
          icon: CupertinoIcons.calendar,
          accent: StairColors.online,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                CupertinoButton(
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                  onPressed: enabled ? () => _move(index, -1) : null,
                  child: const Icon(CupertinoIcons.arrow_up, size: 18),
                ),
              if (index + 1 < rounds.length)
                CupertinoButton(
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                  onPressed: enabled ? () => _move(index, 1) : null,
                  child: const Icon(CupertinoIcons.arrow_down, size: 18),
                ),
              CupertinoButton(
                key: ValueKey('event-round-remove-${rounds[index].id}'),
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
                onPressed: enabled
                    ? () => onChanged(List.of(rounds)..removeAt(index))
                    : null,
                child: const Icon(CupertinoIcons.minus_circle, size: 20),
              ),
            ],
          ),
          children: [
            StageNameRow(
              value: rounds[index].name,
              onChanged: enabled
                  ? (name) => _replace(index, rounds[index].copyWith(name: name))
                  : null,
            ),
            StairDateRow(
              label: '投稿開始',
              value: rounds[index].submissionStart,
              onChanged: enabled
                  ? (date) => _replace(
                        index,
                        rounds[index].copyWith(submissionStart: date),
                      )
                  : null,
            ),
            StairDateRow(
              label: '投稿締切',
              value: rounds[index].submissionEnd,
              onChanged: enabled
                  ? (date) => _replace(
                        index,
                        rounds[index].copyWith(submissionEnd: date),
                      )
                  : null,
            ),
            StairDateRow(
              label: '投票開始',
              value: rounds[index].votingStart,
              onChanged: enabled
                  ? (date) => _replace(
                        index,
                        rounds[index].copyWith(votingStart: date),
                      )
                  : null,
            ),
            StairDateRow(
              label: '投票締切',
              value: rounds[index].votingEnd,
              onChanged: enabled
                  ? (date) => _replace(
                        index,
                        rounds[index].copyWith(votingEnd: date),
                      )
                  : null,
            ),
          ],
        ),
      CupertinoButton(
        key: const ValueKey('event-round-add'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        onPressed: enabled
            ? () => onChanged([
                  ...rounds,
                  EventRound(
                    id: newId(),
                    name: '予選${rounds.length + 1}回戦',
                  ),
                ])
            : null,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.plus_circle, size: 22),
            SizedBox(width: 8),
            Text('日程を追加'),
          ],
        ),
      ),
    ],
  );
}
