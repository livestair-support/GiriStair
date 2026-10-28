import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/event_editor.dart';
import 'screens/event_list.dart';
import 'screens/results.dart';
import 'screens/settings.dart';
import 'screens/thinking.dart';
import 'store.dart';
import 'notifications.dart';
import 'ui/stair_theme.dart';
import 'ui/stair_tab_bar.dart';

class GiriStairApp extends StatefulWidget {
  const GiriStairApp({super.key, required this.store});

  final GiriStore store;

  @override
  State<GiriStairApp> createState() => _GiriStairAppState();
}

class _GiriStairAppState extends State<GiriStairApp>
    with WidgetsBindingObserver {
  late Future<void> _loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_refreshReminders);
    _loading = widget.store.load();
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
        debugShowCheckedModeBanner: false,
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
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
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('GiriStair')),
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
                            _loading = widget.store.load();
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
            return _Home(store: widget.store);
          },
        ),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.store});

  final GiriStore store;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int _selected = 1;

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
            onTap: (index) => setState(() => _selected = index),
          ),
  );
}
