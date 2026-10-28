import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../analytics.dart';
import '../models.dart';
import '../notifications.dart';
import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'players.dart';
import 'sharing.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.store, super.key});
  final GiriStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _expanded = <String>{'share', 'stats', 'directory', 'defaults', 'support'};
  late final Future<String> _version = _loadVersion();
  bool _busy = false;

  Future<String> _loadVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '—';
    }
  }

  void _push(Widget screen) => Navigator.of(context).push<void>(
    CupertinoPageRoute(builder: (_) => screen),
  );

  Future<void> _message(String title, String text) => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );

  Future<void> _savePreferences(AppPreferences preferences) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.savePreferences(preferences);
      await GiriNotifications.instance.sync(widget.store);
    } catch (_) {
      if (mounted) await _message('設定を保存できませんでした', 'もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleNotifications(bool enabled) async {
    if (_busy) return;
    if (enabled) {
      setState(() => _busy = true);
      try {
        final allowed = await GiriNotifications.instance.requestPermission();
        if (!mounted) return;
        if (!allowed) {
          await _message('通知が許可されていません', '端末の「設定」からGiriStairの通知を許可してから、もう一度オンにしてください。');
          return;
        }
      } catch (_) {
        if (mounted) await _message('通知を設定できませんでした', '端末の通知設定を確認して、もう一度お試しください。');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    await _savePreferences(widget.store.preferences.copyWith(notificationsEnabled: enabled));
  }

  Future<void> _backup(BuildContext buttonContext) async {
    if (_busy) return;
    final box = buttonContext.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final filename = 'GiriStair-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
      final result = await SharePlus.instance.share(ShareParams(
        title: 'GiriStairのバックアップ',
        files: [XFile.fromData(Uint8List.fromList(utf8.encode(widget.store.exportBackup())), mimeType: 'application/json', name: filename)],
        fileNameOverrides: [filename],
        sharePositionOrigin: origin,
      ));
      if (result.status == ShareResultStatus.success) await widget.store.recordBackupExported();
    } catch (_) {
      if (mounted) await _message('バックアップを作成できませんでした', '保存先の空き容量を確認して、もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await openFile(acceptedTypeGroups: const [XTypeGroup(
        label: 'GiriStairのバックアップ', extensions: ['json'], mimeTypes: ['application/json'], uniformTypeIdentifiers: ['public.json'],
      )]);
      if (file == null || !mounted) return;
      if (await file.length() > 32 * 1024 * 1024) throw const FormatException('Backup too large.');
      final contents = await file.readAsString();
      final document = jsonDecode(contents);
      if (document is! Map<String, dynamic> || document['schemaVersion'] != 1 || document['events'] is! List || document['notes'] is! List) {
        throw const FormatException('Invalid backup.');
      }
      if (!mounted) return;
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('バックアップから復元しますか？'),
          content: Text('現在の記録・思考メモ・プレイヤー・設定を「${file.name}」の内容に置き換えます。必要な記録は先にバックアップしてください。'),
          actions: [
            CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
            CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: const Text('復元')),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.store.restoreBackup(contents);
      await GiriNotifications.instance.sync(widget.store);
      if (mounted) await _message('復元しました', 'バックアップの記録を読み込みました。');
    } catch (_) {
      if (mounted) await _message('復元できませんでした', 'GiriStairで書き出したJSONファイルか確認してください。不正なデータで現在の記録を上書きすることはありません。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section(String id, String title, IconData icon, Color accent, List<Widget> rows) {
    final expanded = _expanded.contains(id);
    return StairCard(
      accent: accent,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            onTap: () => setState(() { if (!_expanded.add(id)) _expanded.remove(id); }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: StairSectionTitle(title: title, icon: icon, accent: accent, trailing: Icon(
                expanded ? CupertinoIcons.chevron_up_circle : CupertinoIcons.chevron_down_circle, color: accent, size: 19,
              )),
            ),
          ),
        ),
        if (expanded) for (final row in rows) ...[Divider(height: 0.5, color: accent.withValues(alpha: 0.24)), row],
      ]),
    );
  }

  Widget _link(String title, VoidCallback? onTap, {String? detail}) => InkWell(
    onTap: _busy ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 24),
        child: Row(children: [
          Expanded(child: Text(title)),
          if (detail != null) ...[const SizedBox(width: 8), Text(detail, textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall)],
          const SizedBox(width: 8),
          Icon(CupertinoIcons.chevron_right, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
      ),
    ),
  );

  void _guide(String title, List<(String, String)> sections) => _push(_GuideScreen(title: title, sections: sections));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const StairPageHeader(title: '設定', icon: CupertinoIcons.slider_horizontal_3, accent: StairColors.memo),
    body: ListenableBuilder(listenable: widget.store, builder: (context, _) {
      final preferences = widget.store.preferences;
      final backup = widget.store.lastBackupAt;
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
        _section('share', '共有ページ', CupertinoIcons.share, StairColors.live, [
          _link('Giri Summary', () => _push(ShareRecordsScreen(store: widget.store)), detail: '参加回数・戦績'),
          _link('Giri List', () => _push(ShareRecordsScreen(store: widget.store, initialList: true)), detail: '参加記録の一覧'),
        ]),
        _section('stats', '集計', CupertinoIcons.chart_bar, StairColors.result, [
          _link('参加回数・会場・参加者', () => _push(AggregateScreen(store: widget.store))),
        ]),
        _section('directory', '一覧', CupertinoIcons.person_2, StairColors.online, [
          _link('大喜利プレイヤー一覧', () => _push(PlayerDirectoryScreen(store: widget.store)), detail: '名前・フリガナ'),
        ]),
        _section('defaults', 'デフォルト設定', CupertinoIcons.slider_horizontal_3, StairColors.live, [
          StairMenuRow<String>(label: 'テーマ', value: preferences.theme, items: const {'system': '端末に合わせる', 'light': 'ライト', 'dark': 'ダーク', 'stair': 'GiriStair'}, onChanged: _busy ? null : (value) => _savePreferences(preferences.copyWith(theme: value))),
        ]),
        _section('notifications', '通知', CupertinoIcons.bell, StairColors.settings, [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
            const Expanded(child: Text('予定・締切の通知')),
            CupertinoSwitch(value: preferences.notificationsEnabled, activeTrackColor: StairColors.settings, onChanged: _busy ? null : _toggleNotifications),
          ])),
          if (preferences.notificationsEnabled) ...[
            StairMenuRow<int>(label: '開始・締切の前', value: preferences.reminderMinutes, items: const {0: '時刻ちょうど', 15: '15分', 30: '30分', 60: '1時間', 120: '2時間', 1440: '1日'}, onChanged: _busy ? null : (value) => _savePreferences(preferences.copyWith(reminderMinutes: value))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: StairTimeButton(
              label: '時刻未定の当日通知', value: DateTime(2026, 1, 1, preferences.reminderHour, preferences.reminderMinute),
              onChanged: _busy ? null : (value) { if (value != null) _savePreferences(preferences.copyWith(reminderHour: value.hour, reminderMinute: value.minute)); },
            )),
          ],
          Padding(padding: const EdgeInsets.all(16), child: Text('参加予定の開始時刻、ネット大喜利の投稿・投票締切をお知らせします。', style: Theme.of(context).textTheme.bodySmall)),
          ValueListenableBuilder<String?>(valueListenable: GiriNotifications.instance.error, builder: (context, error, _) => error == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.all(16), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
        ]),
        _section('data', 'データ管理', CupertinoIcons.tray, StairColors.memo, [
          Builder(builder: (context) => _link('バックアップを保存', () => _backup(context))),
          _link('バックアップから復元', _restore),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(backup == null ? 'バックアップの書き出し履歴はありません' : '最終書き出し ${backup.year}/${backup.month}/${backup.day} ${backup.hour.toString().padLeft(2, '0')}:${backup.minute.toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text('記録・思考メモ・プレイヤー・設定をJSONにまとめます。保存先で「ファイルに保存」を選んでください。', style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
        _section('support', 'サポート', CupertinoIcons.question_circle, StairColors.venue, [
          _link('はじめにガイド', () => _guide('はじめにガイド', const [
            ('登録', '生大喜利・ネット大喜利を選び、会の名前や日付を入力して保存します。参加後は「参加済み」に変更すると集計に反映されます。'),
            ('参加者', '1人ずつ入力するほか、コピーした名簿や画像からまとめて追加できます。読み取り結果を確認してから追加してください。設定の大喜利プレイヤー一覧でフリガナを編集できます。'),
            ('記録を残す', '大会の順位・結果は戦績、回答案やお題案は思考から振り返れます。設定の共有ページから画像を作成できます。'),
          ])),
          _link('使い方ガイド', () => _guide('使い方ガイド', const [
            ('予定と記録', '一覧から記録を開いて編集できます。生大喜利の時刻がわからないときは日付だけを登録できます。'),
            ('集計', '「参加済み」の記録を対象に参加回数や会場別の回数を集計します。一緒に参加した人の回数は同席回数で、対戦成績ではありません。'),
            ('思考メモ', '投稿期間中のネット大喜利に回答メモを付けられます。期間が終了したり会を削除したりしても、メモ本文は残ります。'),
            ('バックアップ', 'データ管理からJSONを保存してください。復元すると現在の記録全体が置き換わります。アプリを削除すると端末内の記録も失われるため、定期的な保存をおすすめします。'),
          ])),
          _link('プライバシーについて', () => _guide('プライバシーについて', const [
            ('記録の保存', '参加記録、思考メモ、プレイヤーと設定は、この端末のアプリ専用領域に保存します。アカウントの作成や自動クラウド同期はありません。'),
            ('共有とバックアップ', '共有・バックアップを選んだときは、選択したアプリや保存先へデータを渡します。参加者名やメモなど、画像・ファイルに含まれる内容を確認してから共有してください。'),
            ('画像の読み取り', '参加者を読み取る画像は、選択した画像から端末上で文字を認識します。読み取った内容は、確認して追加するまで記録に保存されません。'),
          ])),
          _link('サポート・お問い合わせ', () => _push(const _SupportScreen())),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
            Expanded(child: Text('バージョン', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            FutureBuilder<String>(future: _version, builder: (context, snapshot) => Text(snapshot.data ?? '—')),
          ])),
        ]),
      ]);
    }),
  );
}

class AggregateScreen extends StatefulWidget {
  const AggregateScreen({required this.store, super.key});
  final GiriStore store;
  @override
  State<AggregateScreen> createState() => _AggregateScreenState();
}

class _AggregateScreenState extends State<AggregateScreen> {
  int? _year;

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [Expanded(child: Text(label)), const SizedBox(width: 12), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
  );

  Widget _ranking(String title, IconData icon, Color accent, List<MapEntry<String, int>> counts) => StairSection(
    title: title, icon: icon, accent: accent,
    child: counts.isEmpty ? Text('参加済みの記録に入力すると表示されます。', style: Theme.of(context).textTheme.bodySmall)
      : Column(children: [for (var i = 0; i < counts.length; i++) ...[if (i != 0) const Divider(height: 1), _row('${i + 1}. ${counts[i].key}', '${counts[i].value} 回')]]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('集計')),
    body: ListenableBuilder(listenable: widget.store, builder: (context, _) {
      final years = GiriAnalytics.yearsOf(widget.store.events);
      final selectedYear = years.contains(_year) ? _year : null;
      final stats = GiriAnalytics(widget.store.events, year: selectedYear);
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        StairFormSection(title: '表示する期間', icon: CupertinoIcons.calendar, accent: StairColors.result, children: [
          StairMenuRow<int>(label: '年', value: selectedYear ?? 0, items: {0: 'すべての期間', for (final year in years) year: '$year年'}, onChanged: (value) => setState(() => _year = value == 0 ? null : value)),
        ]),
        StairSection(title: '参加の記録', icon: CupertinoIcons.chart_bar, accent: StairColors.result, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('「参加済み」の記録を集計しています。', style: Theme.of(context).textTheme.bodySmall),
          _row('参加回数', '${stats.attended.length} 回'), const Divider(height: 1),
          _row('生大喜利', '${stats.live.length} 回'), const Divider(height: 1),
          _row('ネット大喜利', '${stats.online.length} 回'), const Divider(height: 1),
          _row('大会への参加', '${stats.tournaments.length} 回'), const Divider(height: 1),
          _row('1位の記録', '${stats.firstPlaceCount} 回'), const Divider(height: 1),
          _row('3位以内の記録', '${stats.podiumCount} 回'),
          Text('順位が入力された大会のみ順位を集計します。日付のない記録は「すべての期間」に含まれます。', style: Theme.of(context).textTheme.bodySmall),
        ])),
        _ranking('よく行く会場', CupertinoIcons.location, StairColors.venue, stats.venues),
        _ranking('一緒に参加した人', CupertinoIcons.person_2, StairColors.online, stats.participants),
        _ranking('主催者別の参加回数', CupertinoIcons.person_crop_circle, StairColors.memo, stats.organizers),
      ]);
    }),
  );
}

class _GuideScreen extends StatelessWidget {
  const _GuideScreen({required this.title, required this.sections});
  final String title;
  final List<(String, String)> sections;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      for (final (heading, body) in sections) StairSection(title: heading, icon: CupertinoIcons.info, accent: StairColors.venue, child: Text(body, style: const TextStyle(height: 1.6))),
    ]),
  );
}

class _SupportScreen extends StatelessWidget {
  const _SupportScreen();
  static const _url = 'https://github.com/livestair-support/GiriStair/issues';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('サポート・お問い合わせ')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      StairSection(title: '不具合・ご要望', icon: CupertinoIcons.chat_bubble, accent: StairColors.venue, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('GiriStairのGitHub Issuesに、操作した画面や発生した内容をお送りください。投稿にはGitHubアカウントが必要です。'),
        const SizedBox(height: 16), const SelectableText(_url), const SizedBox(height: 12),
        TextButton.icon(onPressed: () async {
          await Clipboard.setData(const ClipboardData(text: _url));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('問い合わせ先をコピーしました')));
        }, icon: const Icon(CupertinoIcons.doc_on_clipboard), label: const Text('問い合わせ先をコピー')),
      ])),
    ]),
  );
}
