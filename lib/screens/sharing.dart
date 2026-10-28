import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../analytics.dart';
import '../models.dart';
import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

class ShareRecordsScreen extends StatefulWidget {
  const ShareRecordsScreen({
    required this.store,
    this.initialList = false,
    super.key,
  });

  final GiriStore store;
  final bool initialList;

  @override
  State<ShareRecordsScreen> createState() => _ShareRecordsScreenState();
}

class _ShareRecordsScreenState extends State<ShareRecordsScreen> {
  final _imageKey = GlobalKey();
  late bool _list;
  int? _year;
  int _page = 0;
  bool _showVenues = true;
  bool _showResults = true;
  bool _showParticipants = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _list = widget.initialList;
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _imageKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Preview is not ready.');
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Image could not be generated.');
      if (!buttonContext.mounted) return;
      final box = buttonContext.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'GiriStair-${_list ? 'List' : 'Summary'}.png',
            ),
          ],
          fileNameOverrides: ['GiriStair-${_list ? 'List' : 'Summary'}.png'],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('共有画像を作成できませんでした。もう一度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('共有ページ')),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final events = widget.store.events;
        final years = GiriAnalytics.yearsOf(events);
        // A deleted/restored backup may no longer contain the selected year.
        final selectedYear = years.contains(_year) ? _year : null;
        final analytics = GiriAnalytics(events, year: selectedYear);
        final listEvents =
            events
                .where(
                  (event) =>
                      selectedYear == null ||
                      GiriAnalytics.dateOf(event)?.year == selectedYear,
                )
                .toList()
              ..sort((a, b) {
                final ad = GiriAnalytics.dateOf(a);
                final bd = GiriAnalytics.dateOf(b);
                if (ad == null && bd == null) return a.title.compareTo(b.title);
                if (ad == null) return 1;
                if (bd == null) return -1;
                return ad.compareTo(bd);
              });
        final pages = math.max(1, (listEvents.length / 15).ceil());
        final page = math.min(_page, pages - 1);
        final shown = listEvents.skip(page * 15).take(15).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            StairFormSection(
              title: '表示設定',
              icon: CupertinoIcons.slider_horizontal_3,
              accent: StairColors.settings,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: CupertinoSlidingSegmentedControl<bool>(
                    groupValue: _list,
                    thumbColor: StairColors.action.withValues(alpha: 0.12),
                    children: const {
                      false: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Summary'),
                      ),
                      true: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('List'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _list = value;
                          _page = 0;
                        });
                      }
                    },
                  ),
                ),
                StairMenuRow<int>(
                  label: '期間',
                  value: selectedYear ?? 0,
                  items: {0: 'すべて', for (final year in years) year: '$year年'},
                  onChanged: (value) => setState(() {
                    _year = value == 0 ? null : value;
                    _page = 0;
                  }),
                ),
                _switch(
                  '会場名を表示',
                  _showVenues,
                  (value) => setState(() => _showVenues = value),
                ),
                _switch(
                  '戦績を表示',
                  _showResults,
                  (value) => setState(() => _showResults = value),
                ),
                if (!_list)
                  _switch(
                    '参加者ランキングを表示',
                    _showParticipants,
                    (value) => setState(() => _showParticipants = value),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
              child: Text(
                '下の画像を共有します。名前や会場名など、公開する内容を確認してください。',
                style: TextStyle(fontSize: 13),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: RepaintBoundary(
                  key: _imageKey,
                  child: Theme(
                    data: stairTheme(Brightness.light),
                    child: Material(
                      type: MaterialType.transparency,
                      child: MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.noScaling),
                        child: _ShareImage(
                          list: _list,
                          analytics: analytics,
                          events: shown,
                          period: selectedYear == null
                              ? 'すべての記録'
                              : '$selectedYear年の記録',
                          showVenues: _showVenues,
                          showResults: _showResults,
                          showParticipants: _showParticipants,
                          pageLabel: _list && pages > 1
                              ? '${page + 1} / $pages'
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_list && pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '前のページ',
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    icon: const Icon(CupertinoIcons.chevron_left),
                  ),
                  Text('${page + 1} / $pages ページ'),
                  IconButton(
                    tooltip: '次のページ',
                    onPressed: page + 1 == pages
                        ? null
                        : () => setState(() => _page = page + 1),
                    icon: const Icon(CupertinoIcons.chevron_right),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: _sharing ? null : () => _share(buttonContext),
                icon: const Icon(CupertinoIcons.share),
                label: Text(
                  _sharing
                      ? '画像を作成中…'
                      : _list && pages > 1
                      ? 'このページの画像を共有'
                      : '画像を共有',
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
            const SizedBox(width: 8),
            CupertinoSwitch(
              value: value,
              activeTrackColor: StairColors.settings,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _ShareImage extends StatelessWidget {
  const _ShareImage({
    required this.list,
    required this.analytics,
    required this.events,
    required this.period,
    required this.showVenues,
    required this.showResults,
    required this.showParticipants,
    this.pageLabel,
  });

  final bool list;
  final GiriAnalytics analytics;
  final List<GiriEvent> events;
  final String period;
  final bool showVenues;
  final bool showResults;
  final bool showParticipants;
  final String? pageLabel;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF9F9FB),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'GiriStair',
            style: TextStyle(
              fontSize: 15,
              color: StairColors.action,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            list ? '大喜利 List' : '大喜利 Summary',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            period,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 16),
          if (list) ...[
            if (events.isEmpty) _empty(),
            for (final event in events) _event(event),
          ] else ...[
            StairSection(
              title: '参加の記録',
              icon: CupertinoIcons.calendar,
              accent: StairColors.live,
              child: Column(
                children: [
                  _stat('参加回数', '${analytics.attended.length} 回'),
                  _stat('生大喜利', '${analytics.live.length} 回'),
                  _stat('ネット大喜利', '${analytics.online.length} 回'),
                  _stat('大会', '${analytics.tournaments.length} 回'),
                ],
              ),
            ),
            if (showResults)
              StairSection(
                title: '戦績',
                icon: CupertinoIcons.rosette,
                accent: StairColors.result,
                child: Column(
                  children: [
                    _stat('結果を残した大会', '${analytics.resultCount} 回'),
                    _stat('1位', '${analytics.firstPlaceCount} 回'),
                    _stat('3位以内', '${analytics.podiumCount} 回'),
                    const SizedBox(height: 6),
                    const Text(
                      '順位を入力した大会を集計',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ),
              ),
            if (showVenues)
              _ranking(
                'よく行く会場',
                analytics.venues,
                CupertinoIcons.placemark,
                StairColors.venue,
              ),
            if (showParticipants)
              _ranking(
                '一緒に参加した人',
                analytics.participants,
                CupertinoIcons.person_2,
                StairColors.online,
              ),
          ],
          const SizedBox(height: 16),
          Text(
            pageLabel == null ? 'GiriStair' : 'GiriStair  ·  $pageLabel',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    ),
  );

  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _empty() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Text(
      '記録はまだありません',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
    ),
  );

  Widget _ranking(
    String title,
    List<MapEntry<String, int>> ranking,
    IconData icon,
    Color accent,
  ) => StairSection(
    title: title,
    icon: icon,
    accent: accent,
    child: ranking.isEmpty
        ? _empty()
        : Column(
            children: [
              for (final entry in ranking.take(5))
                _stat(entry.key, '${entry.value} 回'),
            ],
          ),
  );

  Widget _event(GiriEvent event) {
    final date = GiriAnalytics.dateOf(event);
    final status = switch (event.status) {
      EventStatus.planned => '参加予定',
      EventStatus.attended => '参加済み',
      EventStatus.canceled => 'キャンセル',
    };
    return StairCard(
      accent: event.kind == EventKind.live
          ? StairColors.live
          : StairColors.online,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            date == null
                ? '日付未定  ·  $status'
                : '${date.year}/${date.month}/${date.day}  ·  $status',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 3),
          Text(
            event.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (showVenues && event.venue.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              event.venue,
              style: const TextStyle(fontSize: 12, color: Color(0xFF66666D)),
            ),
          ],
          if (showResults &&
              event.meetingType == MeetingType.tournament &&
              (event.placement != null ||
                  event.resultText.trim().isNotEmpty)) ...[
            const SizedBox(height: 3),
            Text(
              [
                if (event.placement != null) '${event.placement}位',
                if (event.resultText.trim().isNotEmpty) event.resultText.trim(),
              ].join('  ·  '),
              style: const TextStyle(fontSize: 12, color: StairColors.result),
            ),
          ],
        ],
      ),
    );
  }
}
