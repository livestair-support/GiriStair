import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/event_editor.dart';
import 'screens/event_list.dart';
import 'screens/results.dart';
import 'screens/settings.dart';
import 'screens/thinking.dart';
import 'store.dart';

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
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFFA44559),
      surface: const Color(0xFFFCF9F6),
    );
    return MaterialApp(
      title: 'GiriStair',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFFF8F4F0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F4F0),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
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
          appBar: AppBar(title: const Text('登録')),
          body: EventEditor(
            store: widget.store,
            onSaved: () => setState(() => _selected = 1),
          ),
        ),
        Scaffold(
          appBar: AppBar(title: const Text('GiriStair')),
          body: EventListScreen(store: widget.store),
        ),
        ResultsScreen(store: widget.store),
        ThinkingScreen(store: widget.store),
        SettingsScreen(store: widget.store),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() => _selected = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: '登録',
        ),
        NavigationDestination(
          icon: Icon(Icons.view_agenda_outlined),
          selectedIcon: Icon(Icons.view_agenda),
          label: '一覧',
        ),
        NavigationDestination(
          icon: Icon(Icons.emoji_events_outlined),
          selectedIcon: Icon(Icons.emoji_events),
          label: '戦績',
        ),
        NavigationDestination(
          icon: Icon(Icons.edit_note_outlined),
          selectedIcon: Icon(Icons.edit_note),
          label: '思考',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '設定',
        ),
      ],
    ),
  );
}
