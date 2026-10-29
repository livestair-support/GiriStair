import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../scheduling.dart';
import '../store.dart';
import '../tournament_presentation.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import '../ui/stair_symbols.dart';
import 'current_calendar.dart';
import 'event_detail.dart';
import 'event_editor.dart' show formatEventDate, eventStatusLabel;
import 'online_site_editor.dart';

export 'event_detail.dart';

String formatCalendarDate(DateTime? value) {
  if (value == null) {
    return '未設定';
  }
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${value.year}年${value.month}月${value.day}日(${weekdays[value.weekday - 1]})';
}

String formatLiveEventDate(GiriEvent event) => event.startsAt != null
    ? formatEventDate(event.startsAt)
    : event.eventDate != null
    ? '${formatCalendarDate(event.eventDate)} · 時刻未定'
    : '日付未設定';

String _shortDate(DateTime? value, {bool compact = false}) {
  if (value == null) {
    return '日付未定';
  }
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${compact ? '' : '${value.year}/'}${value.month}/${value.day}(${weekdays[value.weekday - 1]})';
}

String _time(DateTime? value) => value == null
    ? '--:--'
    : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
Color _accent(GiriEvent event) =>
    event.kind == EventKind.live ? StairColors.live : StairColors.online;
String _kind(GiriEvent event) =>
    event.kind == EventKind.live ? '生大喜利' : 'ネット大喜利';
String _roundLabel(GiriEvent event, EventRound round) => [
  event.meetingType == MeetingType.tournament ? round.name : '投稿・投票',
  if (event.meetingType == MeetingType.tournament || round.promptNumber > 1)
    'お題${round.promptNumber}',
  if (round.block.isNotEmpty) round.block,
].join(' · ');

DateTime? _relevantDate(GiriEvent event, DateTime now) {
  if (event.kind == EventKind.live) {
    return event.eventDate ?? event.startsAt;
  }
  final dates = [
    for (final round in event.effectiveRounds) ...[
      if (round.submissionEnabled) round.submissionEnd,
      if (round.votingRequired) round.votingEnd,
    ],
  ].whereType<DateTime>().toList()..sort();
  return dates.where((date) => !date.isBefore(now)).firstOrNull ??
      dates.lastOrNull;
}

EventRound? _previewRound(GiriEvent event, DateTime now) {
  final deadline = _relevantDate(event, now);
  return event.effectiveRounds
          .where(
            (round) =>
                round.submissionEnd == deadline || round.votingEnd == deadline,
          )
          .firstOrNull ??
      event.effectiveRounds.firstOrNull;
}

class EventListScreen extends StatefulWidget {
  const EventListScreen({required this.store, super.key});
  final GiriStore store;
  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  String _query = '';
  final _search = TextEditingController();
  EventKind? _kindFilter;
  EventStatus? _status;
  bool _attended = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  String? _workingSite;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(GiriEvent event, {bool current = false}) {
    if (current) {
      return event.status != EventStatus.canceled;
    }
    if (!current && event.onlineSiteId != null && !event.isParticipating) {
      return false;
    }
    if (_kindFilter != null && event.kind != _kindFilter) {
      return false;
    }
    if (_status != null && event.status != _status) {
      return false;
    }
    if (!current &&
        _status == null &&
        (event.status == EventStatus.attended) != _attended) {
      return false;
    }
    final site = widget.store.onlineSiteById(event.onlineSiteId);
    final venue = widget.store.venueById(event.venueId);
    return [
      event.title,
      event.organizer,
      event.venue,
      venue?.prefecture ?? '',
      site?.name ?? '',
      event.affiliation,
      event.block,
      ...event.participants,
    ].join(' ').toLowerCase().contains(_query.toLowerCase());
  }

  void _open(GiriEvent event, {String? roundId}) => Navigator.push<void>(
    context,
    CupertinoPageRoute(
      builder: (_) => EventDetailScreen(
        store: widget.store,
        eventId: event.id,
        initialRoundId: roundId,
      ),
    ),
  );

  Future<void> _cycle(OnlineSite site, int offset) async {
    if (_workingSite != null) {
      return;
    }
    setState(() => _workingSite = site.id);
    try {
      final event = await widget.store.createSiteCycle(
        site.id,
        weekOffset: offset,
        join: false,
      );
      if (mounted) {
        _open(event);
      }
    } catch (_) {
      if (mounted) {
        showStairMessage(context, '開催回を開けませんでした。', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _workingSite = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final current = widget.store.preferences.listCurrentMode;
      final now = DateTime.now();
      final events =
          widget.store.events
              .where((event) => _matches(event, current: current))
              .toList()
            ..sort((a, b) {
              final ad = _relevantDate(a, now), bd = _relevantDate(b, now);
              if (ad == null && bd == null) {
                return b.createdAt.compareTo(a.createdAt);
              }
              if (ad == null) {
                return 1;
              }
              if (bd == null) {
                return -1;
              }
              return _attended ? bd.compareTo(ad) : ad.compareTo(bd);
            });
      final periods = currentPeriodsFor(events);
      final sites = _kindFilter == EventKind.live || _attended
          ? <OnlineSite>[]
          : widget.store.onlineSites
                .where(
                  (site) => '${site.name} ${site.affiliation} ${site.block}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()),
                )
                .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (!current)
            StairFormSection(
              title: '表示・検索',
              icon: CupertinoIcons.slider_horizontal_3,
              accent: StairColors.online,
              children: [
                if (!current)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<bool>(
                        key: const ValueKey('list-attendance-tabs'),
                        groupValue: _attended,
                        children: const {
                          false: Text('参加予定'),
                          true: Text('参加済'),
                        },
                        onValueChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _attended = value;
                              _status = null;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    key: const ValueKey('list-search'),
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'タイトル・会場・主催者・参加者で検索',
                      prefixIcon: Icon(CupertinoIcons.search, size: 20),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                ),
                StairMenuRow<int>(
                  key: const ValueKey('list-kind-filter'),
                  label: '形式',
                  accent: StairColors.online,
                  value: _kindFilter?.index ?? -1,
                  items: const {-1: 'すべて', 0: '生大喜利', 1: 'ネット大喜利'},
                  onChanged: (value) => setState(
                    () => _kindFilter = value == -1
                        ? null
                        : EventKind.values[value],
                  ),
                ),
                StairMenuRow<int>(
                  key: const ValueKey('list-status-filter'),
                  label: '参加状況',
                  accent: StairColors.online,
                  value: _status?.index ?? -1,
                  items: {
                    -1: 'すべて',
                    for (final status in EventStatus.values)
                      status.index: eventStatusLabel(status),
                  },
                  onChanged: (value) => setState(() {
                    _status = value == -1 ? null : EventStatus.values[value];
                    if (_status != null) {
                      _attended = _status == EventStatus.attended;
                    }
                  }),
                ),
              ],
            ),
          if (current) ...[
            CurrentCalendar(
              month: _month,
              selected: _selected,
              periods: periods,
              accent: _attended ? StairColors.online : StairColors.action,
              onMonthChanged: (month) => setState(() => _month = month),
              onSelected: (day) => setState(() => _selected = day),
              onOpenPeriod: (period) =>
                  _open(period.event, roundId: period.round?.id),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                formatCalendarDate(_selected),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!periods.any((period) => period.overlapsDay(_selected)))
              _empty('この日の予定はありません'),
            for (final period in periods.where(
              (period) => period.overlapsDay(_selected),
            ))
              _periodCard(period),
          ] else ...[
            for (final site in sites) _siteCard(site),
            if (events.isEmpty && sites.isEmpty)
              _empty(
                widget.store.events.isEmpty && widget.store.onlineSites.isEmpty
                    ? '記録がありません'
                    : '該当する記録がありません',
              ),
            for (final event in events)
              EventListCard(
                store: widget.store,
                event: event,
                onTap: () => _open(event),
              ),
          ],
        ],
      );
    },
  );

  Widget _empty(String text) => StairCard(
    accent: StairColors.online,
    padding: const EdgeInsets.all(24),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const StairIconBadge(
            icon: CupertinoIcons.calendar,
            accent: StairColors.online,
            size: 38,
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );

  Widget _siteCard(OnlineSite site) => StairFormSection(
    key: ValueKey('site-${site.id}'),
    title: site.name,
    icon: CupertinoIcons.globe,
    accent: StairColors.online,
    trailing: CupertinoButton(
      padding: const EdgeInsets.all(4),
      minimumSize: const Size(32, 32),
      onPressed: () => Navigator.push<void>(
        context,
        CupertinoPageRoute(
          builder: (_) => OnlineSiteEditor(store: widget.store, site: site),
        ),
      ),
      child: const Icon(CupertinoIcons.ellipsis, size: 19),
    ),
    children: [
      if (site.affiliation.isNotEmpty || site.block.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            [
              site.affiliation,
              site.block,
            ].where((part) => part.isNotEmpty).join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (var offset = 0; offset < 2; offset++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    key: ValueKey('site-${site.id}-week-$offset'),
                    onPressed: _workingSite == null
                        ? () => _cycle(site, offset)
                        : null,
                    child: Text(
                      site.recurrence == SiteRecurrence.weekly
                          ? (offset == 0 ? '今週' : '来週')
                          : (offset == 0 ? '今回' : '次の回'),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _periodCard(CurrentPeriod period) => StairCard(
    accent: period.color,
    padding: EdgeInsets.zero,
    child: CupertinoButton(
      padding: const EdgeInsets.all(16),
      onPressed: () => _open(period.event, roundId: period.round?.id),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyLarge!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    period.event.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _Badge(period.phase, period.color),
              ],
            ),
            if (period.round != null)
              Text(
                _roundLabel(period.event, period.round!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Text(
              period.kind == CurrentPeriodKind.live
                  ? formatLiveEventDate(period.event)
                  : '${formatEventDate(period.start)} 〜 ${formatEventDate(period.end)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!period.event.isParticipating)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('未参加 · タップして参加・お題を記録'),
              ),
          ],
        ),
      ),
    ),
  );
}

class EventListCard extends StatelessWidget {
  const EventListCard({
    super.key,
    required this.store,
    required this.event,
    required this.onTap,
  });
  final GiriStore store;
  final GiriEvent event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(), date = _relevantDate(event, DateTime.now());
    final venue =
        store.venueById(event.venueId) ??
        store.venueDirectory
            .where((item) => item.name == event.venue)
            .firstOrNull;
    final round = _previewRound(event, now);
    return StairCard(
      key: ValueKey('event-card-${event.id}'),
      accent: _accent(event),
      padding: EdgeInsets.zero,
      child: CupertinoButton(
        padding: const EdgeInsets.all(16),
        onPressed: onTap,
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyLarge!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _CardDate(date: date)),
                  if (event.kind == EventKind.live) ...[
                    Icon(
                      CupertinoIcons.clock,
                      size: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${_time(event.startsAt)} / ${_time(event.endsAt)}',
                      style: StairTypography.role(StairTextRole.caption),
                    ),
                    const SizedBox(width: 7),
                  ],
                  _Badge(_kind(event), _accent(event)),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: StairTypography.style(
                        const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        role: StairTextRole.sectionTitle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    !event.isParticipating
                        ? '未参加'
                        : eventStatusLabel(event.status),
                    _accent(event),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              if (event.kind == EventKind.live) ...[
                _line(
                  context,
                  CupertinoIcons.placemark,
                  [
                    venue?.prefecture ?? '',
                    event.venue,
                  ].where((text) => text.isNotEmpty).join(' · '),
                ),
                if (event.participants.isNotEmpty)
                  _line(
                    context,
                    CupertinoIcons.person_2,
                    event.participants.join('・'),
                    small: true,
                  ),
              ] else if (round != null) ...[
                _line(context, CupertinoIcons.globe, _roundLabel(event, round)),
                if (event.effectiveRounds.length > 1)
                  Text(
                    '${event.effectiveRounds.length}日程',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (round.submissionEnabled && round.submissionEnd != null)
                  Text(
                    '投稿締切 ${formatEventDate(round.submissionEnd)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (round.votingRequired && round.votingEnd != null)
                  Text(
                    '投票締切 ${formatEventDate(round.votingEnd)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ] else
                const Text('スケジュール未設定'),
              if (event.hasRecordedResult)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tournamentResultSummary(event),
                    style: TextStyle(
                      color: StairColors.result,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (eventNeedsResult(event, now))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '結果を入力',
                    style: TextStyle(color: StairColors.action),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(
    BuildContext context,
    IconData icon,
    String text, {
    bool small = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: _accent(event)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text.isEmpty ? '未設定' : text,
            maxLines: small ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: StairTypography.style(
              TextStyle(
                fontSize: small ? 12 : 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: StairTypography.style(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    ),
  );
}

class _CardDate extends StatelessWidget {
  const _CardDate({required this.date});
  final DateTime? date;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = StairTypography.style(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: date == null ? null : calendarDateColor(context, date!),
        ),
        role: StairTextRole.sectionTitle,
      );
      final full = _shortDate(date);
      final painter = TextPainter(
        text: TextSpan(text: full, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final label = painter.width <= constraints.maxWidth
          ? full
          : _shortDate(date, compact: true);
      painter.dispose();
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(label, maxLines: 1, softWrap: false, style: style),
      );
    },
  );
}

/// LiveStair's 44-point circular calendar/list toolbar button.
class EventListModeButton extends StatefulWidget {
  const EventListModeButton({super.key, required this.store});
  final GiriStore store;
  @override
  State<EventListModeButton> createState() => _EventListModeButtonState();
}

class _EventListModeButtonState extends State<EventListModeButton> {
  bool _saving = false;
  Future<void> _toggle() async {
    if (_saving) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final preferences = widget.store.preferences;
      await widget.store.savePreferences(
        preferences.copyWith(listCurrentMode: !preferences.listCurrentMode),
      );
    } catch (_) {
      if (mounted) {
        showStairMessage(context, '表示方法を保存できませんでした。', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final current = widget.store.preferences.listCurrentMode;
      final label = current ? '一覧表示に切り替える' : 'カレンダー表示に切り替える';
      final foreground = Theme.of(context).colorScheme.onSurface;
      return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: CupertinoButton(
            key: const ValueKey('list-mode-button'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: _saving ? null : _toggle,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: foreground.withValues(alpha: .1),
                  width: 1,
                ),
              ),
              child: _saving
                  ? CupertinoActivityIndicator(color: foreground, radius: 9)
                  : StairSymbolIcon(
                      icon: current
                          ? CupertinoIcons.list_bullet
                          : CupertinoIcons.calendar,
                      size: 19,
                      weight: FontWeight.w600,
                      color: foreground,
                    ),
            ),
          ),
        ),
      );
    },
  );
}
