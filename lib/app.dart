import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/event_editor.dart';
import 'screens/event_list.dart';
import 'screens/results.dart';
import 'screens/settings.dart';
import 'screens/thinking.dart';
import 'screens/profile_setup.dart';
import 'store.dart';
import 'notifications.dart';
import 'ui/stair_theme.dart';
import 'ui/stair_tab_bar.dart';
import 'ui/stair_native_controls.dart';
import 'ui/stair_symbols.dart';
import 'ui/stair_maps.dart';
import 'scheduling.dart';
import 'screens/result_entry.dart';

class GiriStairApp extends StatefulWidget {
  const GiriStairApp({super.key, required this.store, this.initialTab = 1, this.navigatorKey})
    : assert(initialTab >= 0 && initialTab < 5);

  final GiriStore store;
  final int initialTab;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<GiriStairApp> createState() => _GiriStairAppState();
}

class _GiriStairAppState extends State<GiriStairApp>
    with WidgetsBindingObserver {
  late Future<void> _loading;
  bool _cycleUpdateFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_refreshReminders);
    _loading = _load();
  }

  Future<void> _load() async {
    _cycleUpdateFailed = false;
    await StairNativeControls.initialize();
    await StairMaps.initialize();
    await StairSymbols.initialize();
    if (mounted) setState(() {});
    await widget.store.load();
    try {
      await widget.store.ensureCurrentSiteCycles();
    } catch (_) {
      // A failed optional cycle write must not hide readable saved records.
      _cycleUpdateFailed = true;
    }
  }

  void _refreshReminders() =>
      unawaited(GiriNotifications.instance.sync(widget.store));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshReminders();
  }

  @override
  void dispose() {
    widget.store.removeListener(_refreshReminders);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => MaterialApp(
        title: 'GiriStair',
        navigatorKey: widget.navigatorKey,
        debugShowCheckedModeBanner: false,
        scrollBehavior: defaultTargetPlatform == TargetPlatform.iOS
            ? const CupertinoScrollBehavior()
            : const MaterialScrollBehavior(),
        locale: StairTypography.locale,
        supportedLocales: const [StairTypography.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: stairTheme(
          Brightness.light,
          warm: widget.store.preferences.theme == 'stair',
        ),
        darkTheme: stairTheme(Brightness.dark),
        themeMode: switch (widget.store.preferences.theme) {
          'system' => ThemeMode.system,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.light,
        },
        home: FutureBuilder<void>(
          future: _loading,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CupertinoActivityIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Scaffold(
                appBar: StairNavigationBar(title: const Text('GiriStair')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_off_outlined, size: 48),
                        const SizedBox(height: 16),
                        const Text('記録を読み込めませんでした'),
                        const SizedBox(height: 8),
                        const Text(
                          '保存済みのデータを保護するため、編集を停止しています。'
                          'アプリを開き直すか、再読み込みを試してください。',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => setState(() {
                            _loading = _load();
                          }),
                          icon: const Icon(Icons.refresh),
                          label: const Text('再読み込み'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (!widget.store.preferences.onboardingCompleted || widget.store.preferences.selfName.trim().isEmpty) {
              return SelfProfileScreen(store: widget.store, initialSetup: true);
            }
            return _Home(store: widget.store, initialTab: widget.initialTab, cycleUpdateFailed: _cycleUpdateFailed);
          },
        ),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.store, required this.initialTab, this.cycleUpdateFailed = false});

  final GiriStore store;
  final int initialTab;
  final bool cycleUpdateFailed;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  late int _selected = widget.initialTab;
  final _promptedResults = <String>{};
  bool _showingResultPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.cycleUpdateFailed) showStairMessage(context, '周期を更新できませんでした。保存済みの記録は表示しています。', error: true);
      _checkResults();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.store.ensureCurrentSiteCycles().catchError((Object error, StackTrace stack) {
        if (mounted) showStairMessage(context, '周期を更新できませんでした。もう一度お試しください。', error: true);
      }));
      _checkResults();
    }
  }

  Future<void> _checkResults() async {
    if (!mounted || _showingResultPrompt || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final pending = widget.store.events.where((event) => !_promptedResults.contains(event.id) && eventNeedsResult(event, DateTime.now())).toList()
      ..sort((a,b) => (b.eventDate ?? b.startsAt ?? b.createdAt).compareTo(a.eventDate ?? a.startsAt ?? a.createdAt));
    if (pending.isEmpty) return;
    final event = pending.first;
    _promptedResults.add(event.id);
    _showingResultPrompt = true;
    try {
      final edit = await showCupertinoDialog<bool>(context: context, builder: (context) => StairCupertinoAlertDialog(
        title: const Text('大会の結果を残しますか？'),
        content: Text(event.title),
        actions: [
          StairCupertinoDialogAction(onPressed: () => Navigator.pop(context,false), child: const Text('後で')),
          StairCupertinoDialogAction(onPressed: () => Navigator.pop(context,true), child: const Text('入力する')),
        ],
      ));
      if (mounted && edit == true) {
        await Navigator.of(context).push<void>(CupertinoPageRoute(builder: (_) => ResultEntryScreen(store: widget.store, eventId: event.id)));
      }
    } finally {
      _showingResultPrompt = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: IndexedStack(
      index: _selected,
      children: [
        EventEditor(
          store: widget.store,
          onSaved: () => setState(() => _selected = 1),
        ),
        Scaffold(
          appBar: const StairPageHeader(
            title: '一覧',
            icon: CupertinoIcons.clock,
            accent: StairColors.online,
          ),
          body: EventListScreen(store: widget.store),
        ),
        ResultsScreen(store: widget.store),
        ThinkingScreen(store: widget.store),
        SettingsScreen(store: widget.store),
      ],
    ),
    bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
        ? null
        : StairTabBar(
            currentIndex: _selected,
            nativeAvailable: StairNativeControls.available,
            onTap: (index) => setState(() => _selected = index),
          ),
  );
}
