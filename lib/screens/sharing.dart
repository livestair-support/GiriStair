import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../analytics.dart';
import '../japanese_holidays.dart';
import '../models.dart';
import '../participant_import.dart';
import '../store.dart';
import '../tournament_presentation.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

/// A cancelled record or an automatically-created, unjoined site cycle is never
/// published. Summary and List apply the same participation boundary.
List<GiriEvent> shareableRecords(
  Iterable<GiriEvent> events, {
  EventStatus? status,
  int? year,
  int monthPeriod = 0,
}) => events.where((event) {
  if (!event.isParticipating || event.status == EventStatus.canceled) {
    return false;
  }
  if (status != null && event.status != status) return false;
  final date = GiriAnalytics.dateOf(event);
  if (year != null && date?.year != year) return false;
  if (monthPeriod == 0) return true;
  if (date == null) return false;
  if (monthPeriod <= 12) return date.month == monthPeriod;
  if (monthPeriod == 101) return date.month <= 6;
  if (monthPeriod == 102) return date.month >= 7;
  final quarter = monthPeriod - 200;
  return quarter >= 1 && quarter <= 4 && (date.month - 1) ~/ 3 + 1 == quarter;
}).toList();

enum _PaperBackground {
  cream,
  white,
  black,
  pink,
  navy,
  creamGradient,
  pinkGradient,
  navyGradient,
  blueGradient,
  photo,
}

enum _PaperText { automatic, black, white, pink }

const _backgroundNames = {
  _PaperBackground.cream: 'GiriStair',
  _PaperBackground.white: '白',
  _PaperBackground.black: '黒',
  _PaperBackground.pink: 'ピンク',
  _PaperBackground.navy: 'ネイビー',
  _PaperBackground.creamGradient: 'GiriStairグラデ',
  _PaperBackground.pinkGradient: 'ピンクグラデ',
  _PaperBackground.navyGradient: 'ネイビーグラデ',
  _PaperBackground.blueGradient: '青白グラデ',
  _PaperBackground.photo: '写真',
};
const _periodNames = {
  0: '全期間',
  101: '上半期',
  102: '下半期',
  201: '1〜3月',
  202: '4〜6月',
  203: '7〜9月',
  204: '10〜12月',
  1: '1月',
  2: '2月',
  3: '3月',
  4: '4月',
  5: '5月',
  6: '6月',
  7: '7月',
  8: '8月',
  9: '9月',
  10: '10月',
  11: '11月',
  12: '12月',
};

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
  int _monthPeriod = 0;
  EventStatus? _target;
  int _page = 0;
  bool _showVenues = true;
  bool _showResults = true;
  bool _showParticipants = false;
  bool _showOrganizers = true;
  bool _showNumber = true;
  bool _sharing = false;
  bool _readingBackground = false;
  _PaperBackground _background = _PaperBackground.creamGradient;
  _PaperText _text = _PaperText.automatic;
  Uint8List? _backgroundBytes;

  @override
  void initState() {
    super.initState();
    _list = widget.initialList;
  }

  Future<void> _pickBackground() async {
    if (_readingBackground) return;
    setState(() => _readingBackground = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) {
        throw const FormatException('3MB以下の画像を選んでください。');
      }
      if (mounted) {
        setState(() {
          _backgroundBytes = bytes;
          _background = _PaperBackground.photo;
        });
      }
    } catch (error) {
      if (mounted) {
        showStairMessage(
          context,
          error is FormatException ? error.message : '背景画像を読み込めませんでした。',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _readingBackground = false);
    }
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
      // Match LiveStair's bounded export rather than allocating an unlimited
      // full-resolution bitmap for a large list.
      final size = boundary.size;
      final scale = math.min(
        2.5,
        math.min(
          16000 / size.height,
          math.sqrt(16000000 / (size.width * size.height)),
        ),
      );
      final image = await boundary.toImage(pixelRatio: math.max(1.0, scale));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Image could not be generated.');
      if (!buttonContext.mounted) return;
      final box = buttonContext.findRenderObject() as RenderBox;
      final name = 'GiriStair-${_list ? 'List' : 'Summary'}.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes.buffer.asUint8List(),
              mimeType: 'image/png',
              name: name,
            ),
          ],
          fileNameOverrides: [name],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        showStairMessage(context, '共有画像を作成できませんでした。もう一度お試しください。', error: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _location(GiriEvent event) {
    if (event.kind == EventKind.online) {
      final site = widget.store.onlineSiteById(event.onlineSiteId);
      final host = Uri.tryParse(event.siteUrl)?.host ?? '';
      return [
        site?.name ?? (host.isEmpty ? 'ネット大喜利' : host),
        event.affiliation,
        event.block,
      ].where((part) => part.trim().isNotEmpty).join(' · ');
    }
    final venue =
        widget.store.venueById(event.venueId) ??
        widget.store.venueDirectory
            .where(
              (venue) =>
                  playerSearchKey(venue.name) == playerSearchKey(event.venue),
            )
            .firstOrNull;
    return [
      venue?.prefecture ?? '',
      venue?.name ?? event.venue,
    ].where((part) => part.trim().isNotEmpty).join(' ');
  }

  double _listCanvasHeight(List<GiriEvent> shown, List<GiriEvent> all) {
    final titleWidth = _showNumber ? 405.0 : 453.0;
    var rowsHeight = 0.0;
    for (final event in shown) {
      var textHeight =
          _measurePaperText(
            event.title,
            14.5,
            FontWeight.w700,
            titleWidth,
            maxLines: 3,
          ) +
          4;
      textHeight += _measurePaperText(
        'ネット大喜利',
        10,
        FontWeight.w700,
        titleWidth,
      );
      if ((_showVenues || event.kind == EventKind.online) &&
          _location(event).isNotEmpty) {
        textHeight += _measurePaperText(
          _location(event),
          11.5,
          FontWeight.w500,
          titleWidth,
        );
      }
      final result = _finalResultLabel(event);
      if (_showResults &&
          event.meetingType == MeetingType.tournament &&
          result.isNotEmpty) {
        textHeight += _measurePaperText(
          result,
          11,
          FontWeight.w600,
          titleWidth,
        );
      }
      rowsHeight += math.max(58.0, textHeight) + 18.7;
    }
    final yearCount = all
        .map(GiriAnalytics.dateOf)
        .whereType<DateTime>()
        .map((date) => date.year)
        .toSet()
        .length;
    var yearHeaders = 0;
    if (yearCount > 1) {
      for (var index = 0; index < shown.length; index++) {
        if (index == 0 ||
            GiriAnalytics.dateOf(shown[index - 1])?.year !=
                GiriAnalytics.dateOf(shown[index])?.year) {
          yearHeaders++;
        }
      }
    }
    return math.max(842.0, 260.0 + rowsHeight + yearHeaders * 28.0);
  }

  double _summaryCanvasHeight(GiriAnalytics analytics) {
    double rankingHeight(List<MapEntry<String, int>> entries) =>
        44.0 +
        (entries.isEmpty ? 36.0 : math.min(5, entries.length) * 29.0) +
        (entries.length > 5 ? 15.0 : 0.0);
    final left =
        (_showParticipants ? rankingHeight(analytics.coParticipants) : 0.0) +
        (_showOrganizers ? rankingHeight(analytics.organizers) : 0.0);
    final right =
        (_showVenues ? rankingHeight(analytics.venues) : 0.0) +
        rankingHeight(analytics.sites);
    return math.max(650.0, 310.0 + math.max(left, right));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(
      title: Text(_list ? 'Giri List' : 'Giri Summary'),
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final eligible = shareableRecords(widget.store.events);
        final years = GiriAnalytics.yearsOf(eligible);
        final selectedYear = years.contains(_year) ? _year : null;
        final filtered = shareableRecords(
          eligible,
          year: selectedYear,
          monthPeriod: _monthPeriod,
        );
        final analytics = GiriAnalytics(
          filtered,
          selfName: widget.store.preferences.selfName,
          siteNames: {
            for (final site in widget.store.onlineSites) site.id: site.name,
          },
        );
        final allListEvents = shareableRecords(filtered, status: _target)
          ..sort((a, b) {
            final group = (a.status == EventStatus.planned ? 1 : 0).compareTo(
              b.status == EventStatus.planned ? 1 : 0,
            );
            if (group != 0) return group;
            final ad = GiriAnalytics.dateOf(a);
            final bd = GiriAnalytics.dateOf(b);
            if (ad == null && bd == null) return a.title.compareTo(b.title);
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });
        final pages = math.max(1, (allListEvents.length / 15).ceil());
        final page = math.min(_page, pages - 1);
        final shown = allListEvents.skip(page * 15).take(15).toList();
        final width = _list ? 595.0 : 390.0;
        // A4 is the minimum List size. Long names are bounded to three lines,
        // and each explicit page is tall enough to keep every row readable.
        final height = _list
            ? _listCanvasHeight(shown, allListEvents)
            : _summaryCanvasHeight(analytics);
        final period =
            '${selectedYear == null ? '全期間' : '$selectedYear年'}${_monthPeriod == 0 ? '' : ' · ${_periodNames[_monthPeriod]}'}';
        final darkPaper =
            _background == _PaperBackground.black ||
            _background == _PaperBackground.navy ||
            _background == _PaperBackground.navyGradient;
        final foreground = switch (_text) {
          _PaperText.black => Colors.black,
          _PaperText.white => Colors.white,
          _PaperText.pink => StairColors.action,
          _PaperText.automatic => darkPaper ? Colors.white : Colors.black,
        };
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StairFormSection(
                title: '表示設定',
                icon: CupertinoIcons.slider_horizontal_3,
                accent: StairColors.settings,
                children: [
                  StairMenuRow<bool>(
                    key: const ValueKey('share-image-kind'),
                    label: '画像',
                    value: _list,
                    accent: StairColors.settings,
                    items: const {false: 'Summary', true: 'List'},
                    onChanged: (value) => setState(() {
                      _list = value;
                      _page = 0;
                    }),
                  ),
                  StairMenuRow<int>(
                    key: const ValueKey('share-year'),
                    label: '年',
                    accent: StairColors.settings,
                    value: selectedYear ?? 0,
                    items: {0: '全期間', for (final year in years) year: '$year年'},
                    onChanged: (value) => setState(() {
                      _year = value == 0 ? null : value;
                      _page = 0;
                    }),
                  ),
                  StairMenuRow<int>(
                    key: const ValueKey('share-month'),
                    label: '月',
                    accent: StairColors.settings,
                    value: _monthPeriod,
                    items: _periodNames,
                    onChanged: (value) => setState(() {
                      _monthPeriod = value;
                      _page = 0;
                    }),
                  ),
                  if (_list)
                    StairMenuRow<int>(
                      key: const ValueKey('share-status'),
                      label: '対象',
                      accent: StairColors.settings,
                      value: _target?.index ?? -1,
                      items: const {-1: 'すべて', 0: '参加予定', 1: '参加済み'},
                      onChanged: (value) => setState(() {
                        _target = value < 0 ? null : EventStatus.values[value];
                        _page = 0;
                      }),
                    ),
                  _switch(
                    '会場名を表示',
                    _showVenues,
                    (value) => setState(() => _showVenues = value),
                    key: 'share-show-venues',
                  ),
                  _switch(
                    '戦績を表示',
                    _showResults,
                    (value) => setState(() => _showResults = value),
                    key: 'share-show-results',
                  ),
                  if (!_list) ...[
                    _switch(
                      '参加者ランキングを表示',
                      _showParticipants,
                      (value) => setState(() => _showParticipants = value),
                      key: 'share-show-participants',
                    ),
                    _switch(
                      '主催者ランキングを表示',
                      _showOrganizers,
                      (value) => setState(() => _showOrganizers = value),
                      key: 'share-show-organizers',
                    ),
                  ] else
                    _switch(
                      '通し番号を表示',
                      _showNumber,
                      (value) => setState(() => _showNumber = value),
                      key: 'share-show-number',
                    ),
                  StairMenuRow<_PaperBackground>(
                    key: const ValueKey('share-background'),
                    label: '背景',
                    value: _background,
                    accent: StairColors.settings,
                    items: _backgroundNames,
                    onChanged: _readingBackground
                        ? null
                        : (value) {
                            if (value == _PaperBackground.photo &&
                                _backgroundBytes == null) {
                              _pickBackground();
                            } else {
                              setState(() => _background = value);
                            }
                          },
                  ),
                  if (_background == _PaperBackground.photo)
                    CupertinoButton(
                      onPressed: _readingBackground ? null : _pickBackground,
                      child: Text(_readingBackground ? '読み込み中' : '背景写真を変更'),
                    ),
                  StairMenuRow<_PaperText>(
                    key: const ValueKey('share-text-color'),
                    label: '文字色',
                    value: _text,
                    accent: StairColors.settings,
                    items: const {
                      _PaperText.automatic: '標準',
                      _PaperText.black: '黒',
                      _PaperText.white: '白',
                      _PaperText.pink: 'ピンク',
                    },
                    onChanged: (value) => setState(() => _text = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = math.min(1.0, constraints.maxWidth / width);
                  return Center(
                    child: SizedBox(
                      width: width * scale,
                      height: height * scale,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: width,
                        maxWidth: width,
                        minHeight: height,
                        maxHeight: height,
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.topLeft,
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
                                  child: _SharePaper(
                                    key: const ValueKey('share-canvas'),
                                    list: _list,
                                    width: width,
                                    height: height,
                                    analytics: analytics,
                                    events: shown,
                                    allEvents: allListEvents,
                                    locations: {
                                      for (final event in shown)
                                        event.id: _location(event),
                                    },
                                    period: period,
                                    foreground: foreground,
                                    background: _background,
                                    backgroundBytes: _backgroundBytes,
                                    showVenues: _showVenues,
                                    showResults: _showResults,
                                    showParticipants: _showParticipants,
                                    showOrganizers: _showOrganizers,
                                    showNumber: _showNumber,
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
                    ),
                  );
                },
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
                  key: const ValueKey('share-export'),
                  onPressed: _sharing || _readingBackground
                      ? null
                      : () => _share(buttonContext),
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
          ),
        );
      },
    ),
  );

  Widget _switch(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    required String key,
  }) => StairFormRow(
    label: label,
    child: Align(
      alignment: Alignment.centerRight,
      child: CupertinoSwitch(
        key: ValueKey(key),
        value: value,
        activeTrackColor: StairColors.settings,
        onChanged: onChanged,
      ),
    ),
  );
}

TextStyle _paperStyle(
  double size,
  FontWeight weight,
  Color color, {
  double? tracking,
}) => StairTypography.style(
  TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: tracking,
  ),
);

double _measurePaperText(
  String text,
  double size,
  FontWeight weight,
  double width, {
  int maxLines = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _paperStyle(size, weight, Colors.black)),
    textDirection: TextDirection.ltr,
    locale: StairTypography.locale,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

String _finalResultLabel(GiriEvent event) {
  final outcome = event.tournamentResult?.outcome;
  final rank = event.effectivePlacement;
  return [
    if (outcome != null &&
        outcome != TournamentOutcome.unrecorded &&
        outcome != TournamentOutcome.advanced)
      tournamentOutcomeLabel(outcome),
    if (rank != null &&
        outcome != TournamentOutcome.champion &&
        outcome != TournamentOutcome.runnerUp)
      '$rank位',
  ].join(' · ');
}

class _SharePaper extends StatelessWidget {
  const _SharePaper({
    super.key,
    required this.list,
    required this.width,
    required this.height,
    required this.analytics,
    required this.events,
    required this.allEvents,
    required this.locations,
    required this.period,
    required this.foreground,
    required this.background,
    required this.backgroundBytes,
    required this.showVenues,
    required this.showResults,
    required this.showParticipants,
    required this.showOrganizers,
    required this.showNumber,
    this.pageLabel,
  });
  final bool list;
  final double width;
  final double height;
  final GiriAnalytics analytics;
  final List<GiriEvent> events;
  final List<GiriEvent> allEvents;
  final Map<String, String> locations;
  final String period;
  final Color foreground;
  final _PaperBackground background;
  final Uint8List? backgroundBytes;
  final bool showVenues;
  final bool showResults;
  final bool showParticipants;
  final bool showOrganizers;
  final bool showNumber;
  final String? pageLabel;

  Color get muted => foreground.withValues(alpha: .6);
  Color get rule => foreground.withValues(alpha: .14);

  BoxDecoration get decoration {
    final colors = switch (background) {
      _PaperBackground.creamGradient => const [
        Color(0xFFFFE0ED),
        Color(0xFFFAEDD6),
        Color(0xFFFFF7DB),
      ],
      _PaperBackground.pinkGradient => const [
        Color(0xFFFFCCE6),
        Color(0xFFFFF0FA),
        Color(0xFFD6B3E6),
      ],
      _PaperBackground.navyGradient => const [
        Color(0xFF080A12),
        Color(0xFF1C1F33),
        Color(0xFF61668C),
      ],
      _PaperBackground.blueGradient => const [
        Color(0xFFFAFAF2),
        Color(0xFFE0F5FC),
        Color(0xFF6BC7EB),
      ],
      _ => null,
    };
    final color = switch (background) {
      _PaperBackground.white => Colors.white,
      _PaperBackground.black => Colors.black,
      _PaperBackground.pink => const Color(0xFFFFE6F0),
      _PaperBackground.navy => const Color(0xFF141A2E),
      _ => const Color(0xFFFAEDD6),
    };
    return BoxDecoration(
      color: colors == null ? color : null,
      gradient: colors == null
          ? null
          : LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      image: background == _PaperBackground.photo && backgroundBytes != null
          ? DecorationImage(
              image: MemoryImage(backgroundBytes!),
              fit: BoxFit.cover,
            )
          : null,
      borderRadius: list ? null : BorderRadius.circular(26),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: decoration,
      child: DefaultTextStyle(
        style: _paperStyle(14, FontWeight.w400, foreground),
        child: Padding(
          padding: list
              ? const EdgeInsets.fromLTRB(32, 30, 32, 28)
              : const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              if (list) ...[
                const SizedBox(height: 10),
                Expanded(child: _listBody()),
              ] else ...[
                const SizedBox(height: 8),
                _kindCounts(),
                const SizedBox(height: 12),
                Expanded(child: _summaryRankings()),
                if (showResults) _finalResults(),
              ],
              const SizedBox(height: 10),
              Text(
                pageLabel == null ? 'GiriStair' : 'GiriStair  ·  $pageLabel',
                textAlign: TextAlign.right,
                style: _paperStyle(10, FontWeight.w600, muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list ? 'GIRI LIST' : 'GIRI SUMMARY',
                  style: _paperStyle(
                    list ? 36 : 28,
                    FontWeight.w900,
                    foreground,
                    tracking: -1,
                  ),
                  maxLines: 1,
                ),
                Text(
                  list ? 'MY OGIRI HISTORY & SCHEDULE' : 'MY OGIRI ARCHIVE',
                  style: _paperStyle(
                    list ? 9 : 8,
                    FontWeight.w600,
                    muted,
                    tracking: 1.8,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'GiriStair',
              style: _paperStyle(13, FontWeight.w700, muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list ? '期間' : '集計期間',
                  style: _paperStyle(11, FontWeight.w700, StairColors.action),
                ),
                const SizedBox(height: 4),
                Text(
                  period,
                  style: _paperStyle(
                    list ? 18 : 15,
                    FontWeight.w800,
                    foreground,
                  ),
                ),
              ],
            ),
          ),
          if (list) ...[
            _count(
              '参加済み',
              allEvents
                  .where((event) => event.status == EventStatus.attended)
                  .length,
              30,
            ),
            const SizedBox(width: 16),
            _count(
              '参加予定',
              allEvents
                  .where((event) => event.status == EventStatus.planned)
                  .length,
              30,
            ),
          ] else
            _count('参加した大喜利', analytics.attended.length, 36),
        ],
      ),
      const SizedBox(height: 10),
      Divider(height: 1, thickness: .8, color: rule),
    ],
  );

  Widget _count(String label, int count, double size) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: _paperStyle(11, FontWeight.w700, StairColors.action)),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$count',
            style: _paperStyle(size, FontWeight.w900, StairColors.action),
          ),
          const SizedBox(width: 3),
          Text('回', style: _paperStyle(12, FontWeight.w700, foreground)),
        ],
      ),
    ],
  );

  Widget _kindCounts() => Row(
    children: [
      Expanded(child: _kindCount('生大喜利', analytics.live.length)),
      Container(height: 42, width: 1, color: rule),
      Expanded(child: _kindCount('ネット大喜利', analytics.online.length)),
    ],
  );
  Widget _kindCount(String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        Text(label, style: _paperStyle(12, FontWeight.w700, muted)),
        Text('$count', style: _paperStyle(27, FontWeight.w900, foreground)),
      ],
    ),
  );

  Widget _summaryRankings() => LayoutBuilder(
    builder: (context, constraints) {
      final leftWidth = (constraints.maxWidth - 19) * .54;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: leftWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showParticipants)
                  _ranking('一緒に参加した人', 'TOP PLAYERS', analytics.coParticipants),
                if (showOrganizers)
                  _ranking('主催者', 'TOP ORGANIZERS', analytics.organizers),
                if (!showParticipants && !showOrganizers) _empty(),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Container(width: 1, color: rule),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showVenues) _ranking('会場', 'TOP VENUES', analytics.venues),
                _ranking('サイト', 'TOP SITES', analytics.sites),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _ranking(
    String title,
    String english,
    List<MapEntry<String, int>> ranking,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: _paperStyle(13, FontWeight.w800, foreground),
          maxLines: 1,
        ),
        Text(
          english,
          style: _paperStyle(7.5, FontWeight.w600, muted, tracking: .8),
        ),
        const SizedBox(height: 5),
        Divider(height: 1, thickness: .8, color: rule),
        if (ranking.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('記録なし', style: _paperStyle(11, FontWeight.w400, muted)),
          )
        else
          for (var index = 0; index < math.min(5, ranking.length); index++)
            SizedBox(
              height: 29,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${index + 1}',
                      style: _paperStyle(
                        14,
                        FontWeight.w800,
                        StairColors.action,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ranking[index].key,
                      style: _paperStyle(11.5, FontWeight.w600, foreground),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${ranking[index].value}',
                    style: _paperStyle(13, FontWeight.w800, foreground),
                  ),
                ],
              ),
            ),
        if (ranking.length > 5)
          Text(
            'ほか${ranking.length - 5}件',
            style: _paperStyle(9, FontWeight.w400, muted),
          ),
      ],
    ),
  );

  Widget _finalResults() => Column(
    children: [
      Divider(height: 1, thickness: .8, color: rule),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _metric('大会', analytics.tournaments.length)),
          Expanded(child: _metric('優勝', analytics.firstPlaceCount)),
          Expanded(child: _metric('準優勝', analytics.runnerUpCount)),
          Expanded(child: _metric('入賞', analytics.placedCount)),
        ],
      ),
    ],
  );
  Widget _metric(String label, int value) => Column(
    key: ValueKey('share-metric-$label'),
    children: [
      Text(label, style: _paperStyle(10, FontWeight.w600, muted)),
      Text('$value', style: _paperStyle(21, FontWeight.w900, foreground)),
    ],
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      '記録はまだありません',
      textAlign: TextAlign.center,
      style: _paperStyle(14, FontWeight.w600, muted),
    ),
  );

  Widget _listBody() {
    final upcoming = allEvents
        .where((event) => event.status == EventStatus.planned)
        .firstOrNull;
    final boundary =
        allEvents.any((event) => event.status == EventStatus.attended)
        ? upcoming?.id
        : null;
    final multipleYears =
        allEvents
            .map(GiriAnalytics.dateOf)
            .whereType<DateTime>()
            .map((date) => date.year)
            .toSet()
            .length >
        1;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (events.isEmpty) _empty(),
        for (var index = 0; index < events.length; index++) ...[
          if (multipleYears &&
              (index == 0 ||
                  GiriAnalytics.dateOf(events[index - 1])?.year !=
                      GiriAnalytics.dateOf(events[index])?.year))
            _yearHeader(GiriAnalytics.dateOf(events[index])),
          if (events[index].id == boundary) _upcomingDivider(),
          _eventRow(
            events[index],
            next: events[index].id == upcoming?.id,
            now: now,
          ),
          if (index + 1 < events.length && events[index + 1].id != boundary)
            Divider(height: .7, thickness: .7, color: rule),
        ],
      ],
    );
  }

  Widget _yearHeader(DateTime? date) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 2),
    child: Row(
      children: [
        Text(
          date == null ? '日付未定' : '${date.year}年',
          style: _paperStyle(14, FontWeight.w900, StairColors.action),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            height: 1,
            thickness: .8,
            color: StairColors.action.withValues(alpha: .22),
          ),
        ),
      ],
    ),
  );
  Widget _upcomingDivider() => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Row(
      children: [
        Container(width: 18, height: 1.6, color: StairColors.action),
        const SizedBox(width: 8),
        Text(
          'これからの大喜利',
          style: _paperStyle(11, FontWeight.w800, StairColors.action),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1.6, color: StairColors.action)),
      ],
    ),
  );

  Widget _eventRow(
    GiriEvent event, {
    required bool next,
    required DateTime now,
  }) {
    final date = GiriAnalytics.dateOf(event);
    final today =
        date != null &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final weekdayColor = date == null
        ? muted
        : date.weekday == DateTime.sunday || isJapaneseHoliday(date)
        ? CupertinoColors.systemRed
        : date.weekday == DateTime.saturday
        ? CupertinoColors.systemBlue
        : muted;
    final number = allEvents.indexWhere((item) => item.id == event.id) + 1;
    final finalResult = _finalResultLabel(event);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date == null ? '未定' : '${date.month}/${date.day}',
                  style: _paperStyle(20, FontWeight.w800, foreground),
                ),
                Text(
                  date == null
                      ? '日付未定'
                      : '${weekdays[date.weekday - 1]}曜日${isJapaneseHoliday(date) ? '・祝' : ''}',
                  style: _paperStyle(10, FontWeight.w700, weekdayColor),
                ),
                if (today || next)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: StairColors.action,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          today ? 'TODAY' : 'NEXT',
                          style: _paperStyle(
                            8.5,
                            FontWeight.w900,
                            Colors.white,
                            tracking: .8,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  event.title,
                  style: _paperStyle(14.5, FontWeight.w700, foreground),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  event.kind == EventKind.live ? '生大喜利' : 'ネット大喜利',
                  style: _paperStyle(10, FontWeight.w700, muted),
                ),
                if ((showVenues || event.kind == EventKind.online) &&
                    locations[event.id]?.isNotEmpty == true)
                  Text(
                    locations[event.id]!,
                    style: _paperStyle(11.5, FontWeight.w500, muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (showResults &&
                    event.meetingType == MeetingType.tournament &&
                    finalResult.isNotEmpty)
                  Text(
                    finalResult,
                    style: _paperStyle(11, FontWeight.w600, foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (showNumber) ...[
            const SizedBox(width: 10),
            Text('#$number', style: _paperStyle(11, FontWeight.w700, muted)),
          ],
        ],
      ),
    );
  }
}
