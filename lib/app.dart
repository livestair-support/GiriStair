import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/event_editor.dart';
import 'screens/event_list.dart';
import 'screens/results.dart';
import 'screens/settings.dart';
import 'screens/thinking.dart';
import 'store.dart';
import 'ui/stair_theme.dart';

class GiriStairApp extends StatefulWidget {
  const GiriStairApp({super.key, required this.store});

  final GiriStore store;

  @override
  State<GiriStairApp> createState() => _GiriStairAppState();
}

class _GiriStairAppState extends State<GiriStairApp> {
  late Future<void> _loading;

  @override
  void initState() {
    super.initState();
    _loading = widget.store.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GiriStair',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: stairTheme(Brightness.light),
      darkTheme: stairTheme(Brightness.dark),
      themeMode: ThemeMode.system,
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
    body: IndexedStack(
      index: _selected,
      children: [
        Scaffold(
          appBar: const StairPageHeader(
            title: '登録',
            icon: Icons.add_circle,
            accent: StairColors.live,
          ),
          body: EventEditor(
            store: widget.store,
            onSaved: () => setState(() => _selected = 1),
          ),
        ),
        Scaffold(
          appBar: const StairPageHeader(
            title: '一覧',
            icon: Icons.history,
            accent: StairColors.online,
          ),
          body: EventListScreen(store: widget.store),
        ),
        ResultsScreen(store: widget.store),
        ThinkingScreen(store: widget.store),
        SettingsScreen(store: widget.store),
      ],
    ),
    bottomNavigationBar: CupertinoTabBar(
      currentIndex: _selected,
      onTap: (index) => setState(() => _selected = index),
      activeColor: StairColors.action,
      inactiveColor: Theme.of(context).colorScheme.onSurfaceVariant,
      backgroundColor: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.add_circle_outline),
          activeIcon: Icon(Icons.add_circle),
          label: '登録',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_outlined),
          activeIcon: Icon(Icons.history),
          label: '一覧',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.emoji_events_outlined),
          activeIcon: Icon(Icons.emoji_events),
          label: '戦績',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.edit_note_outlined),
          activeIcon: Icon(Icons.edit_note),
          label: '思考',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: '設定',
        ),
      ],
    ),
  );
}
