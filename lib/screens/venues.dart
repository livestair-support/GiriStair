import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../participant_import.dart';
import '../store.dart';
import '../ui/player_widgets.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_maps.dart';
import '../ui/stair_native_controls.dart';
import '../ui/stair_theme.dart';
import 'event_list.dart';

class VenueDirectoryScreen extends StatefulWidget {
  const VenueDirectoryScreen({super.key, required this.store});
  final GiriStore store;

  @override
  State<VenueDirectoryScreen> createState() => _VenueDirectoryScreenState();
}

class _VenueDirectoryScreenState extends State<VenueDirectoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(
      title: const Text('会場一覧'),
      actions: [
        StairBarButton(
          onPressed: () => Navigator.of(context).push<GiriVenue>(
            CupertinoPageRoute(
              builder: (_) => VenueEditorScreen(store: widget.store),
            ),
          ),
          child: const Icon(CupertinoIcons.plus),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final query = playerSearchKey(_query);
        final venues = widget.store.venueDirectory
            .where(
              (venue) => playerSearchKey(
                '${venue.name} ${venue.prefecture}',
              ).contains(query),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            StairFormSection(
              title: '表示・検索',
              icon: CupertinoIcons.search,
              accent: StairColors.venue,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: '会場名・都道府県で検索',
                      prefixIcon: Icon(CupertinoIcons.search, size: 19),
                    ),
                  ),
                ),
              ],
            ),
            StairFormSection(
              title: '会場',
              icon: CupertinoIcons.placemark,
              accent: StairColors.venue,
              children: [
                if (venues.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(query.isEmpty ? '会場を追加してください' : '一致する会場がありません'),
                  ),
                for (final venue in venues)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    onPressed: () => Navigator.of(context).push<void>(
                      CupertinoPageRoute(
                        builder: (_) => VenueDetailScreen(
                          store: widget.store,
                          venueId: venue.id,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue.name,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              if (venue.prefecture.isNotEmpty)
                                Text(
                                  venue.prefecture,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.chevron_right, size: 15),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class VenueDetailScreen extends StatefulWidget {
  const VenueDetailScreen({
    super.key,
    required this.store,
    required this.venueId,
  });
  final GiriStore store;
  final String venueId;

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  late String _venueId = widget.venueId;
  String? _lastName;
  bool _savingMap = false;

  Future<void> _changeMap(GiriVenue venue) async {
    if (_savingMap) return;
    setState(() => _savingMap = true);
    try {
      final place = await StairMaps.pickPlace(
        initialQuery: '${venue.prefecture} ${venue.name}'.trim(),
        dark: Theme.of(context).brightness == Brightness.dark,
      );
      if (place == null || !mounted) return;
      final prefecture = japanesePrefectures
          .where(place.address.contains)
          .firstOrNull;
      await widget.store.saveVenue(
        venue.copyWith(
          latitude: place.latitude,
          longitude: place.longitude,
          mapAddress: place.address,
          prefecture: venue.prefecture.isEmpty
              ? prefecture ?? ''
              : venue.prefecture,
        ),
      );
      final saved = widget.store.venueDirectory
          .where((item) => item.name == venue.name)
          .firstOrNull;
      if (mounted && saved != null) setState(() => _venueId = saved.id);
    } catch (_) {
      if (mounted) showStairMessage(context, '地図を保存できませんでした。', error: true);
    } finally {
      if (mounted) setState(() => _savingMap = false);
    }
  }

  Future<void> _clearMap(GiriVenue venue) async {
    if (_savingMap) return;
    setState(() => _savingMap = true);
    try {
      await widget.store.saveVenue(
        venue.copyWith(latitude: null, longitude: null, mapAddress: ''),
      );
    } catch (_) {
      if (mounted) showStairMessage(context, '地図の登録を解除できませんでした。', error: true);
    } finally {
      if (mounted) setState(() => _savingMap = false);
    }
  }

  Future<void> _edit(GiriVenue venue) async {
    final saved = await Navigator.of(context).push<GiriVenue>(
      CupertinoPageRoute(
        builder: (_) => VenueEditorScreen(store: widget.store, venue: venue),
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        _venueId = saved.id;
        _lastName = saved.name;
      });
    }
  }

  Future<void> _launch(Uri uri) async {
    try {
      if (!['http', 'https'].contains(uri.scheme) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('地図を開けませんでした。');
      }
    } catch (_) {
      if (mounted) showStairMessage(context, '地図を開けませんでした。', error: true);
    }
  }

  Uri _mapUri(GiriVenue venue, {required bool google}) {
    final query = venue.latitude != null && venue.longitude != null
        ? '${venue.latitude},${venue.longitude}'
        : '${venue.prefecture} ${venue.name}'.trim();
    return google
        ? Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': query,
          })
        : Uri.https('maps.apple.com', '/', {
            'q': venue.latitude != null && venue.longitude != null
                ? venue.name
                : query,
            if (venue.latitude != null && venue.longitude != null) 'll': query,
          });
  }

  Future<void> _chooseMap(GiriVenue venue) async {
    final registered = Uri.tryParse(venue.mapUrl);
    final choice = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(venue.name),
        actions: [
          if (registered != null &&
              ['https', 'http'].contains(registered.scheme))
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('登録した地図で開く'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 1),
            child: const Text('Appleマップで開く'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 2),
            child: const Text('Googleマップで開く'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _launch(
      choice == 0 ? registered! : _mapUri(venue, google: choice == 2),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final venue =
          store.venueById(_venueId) ??
          store.venueDirectory
              .where((venue) => venue.name == _lastName)
              .firstOrNull;
      if (venue == null) {
        return Scaffold(
          appBar: StairNavigationBar(title: const Text('会場')),
          body: const Center(child: Text('会場の登録情報がありません')),
        );
      }
      _lastName = venue.name;
      final visits = store.events
          .where(
            (event) =>
                event.status == EventStatus.attended &&
                event.kind == EventKind.live &&
                (event.venueId == venue.id ||
                    playerSearchKey(event.venue) ==
                        playerSearchKey(venue.name)),
          )
          .toList();
      return Scaffold(
        appBar: StairNavigationBar(
          title: const Text('会場'),
          actions: [
            StairBarButton(
              onPressed: _savingMap ? null : () => _edit(venue),
              child: const Text('編集'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            StairCard(
              accent: StairColors.venue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venue.name,
                    key: const ValueKey('venue-detail-name'),
                    style: StairTypography.role(StairTextRole.pageTitle),
                  ),
                  if (venue.prefecture.isNotEmpty) Text(venue.prefecture),
                  const SizedBox(height: 8),
                  Text('参加 ${visits.length}回'),
                ],
              ),
            ),
            StairFormSection(
              title: 'マップ',
              icon: CupertinoIcons.map,
              accent: StairColors.venue,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (StairMaps.available)
                    CupertinoButton(
                      key: const ValueKey('venue-detail-map-select'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(40, 28),
                      onPressed: _savingMap ? null : () => _changeMap(venue),
                      child: Text(venue.latitude == null ? '登録' : '変更'),
                    ),
                  if (venue.latitude != null && venue.longitude != null)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(40, 28),
                      onPressed: _savingMap ? null : () => _clearMap(venue),
                      child: const Text('解除'),
                    ),
                ],
              ),
              children: [
                if (venue.latitude != null && venue.longitude != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: StairMapPreview(
                      latitude: venue.latitude!,
                      longitude: venue.longitude!,
                      name: venue.name,
                      onTap: () => _chooseMap(venue),
                    ),
                  ),
                if (venue.mapAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(venue.mapAddress),
                  ),
                CupertinoButton(
                  onPressed: () => _chooseMap(venue),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.map, size: 20),
                      SizedBox(width: 8),
                      Text('マップを開く'),
                    ],
                  ),
                ),
              ],
            ),
            if (venue.memo.isNotEmpty)
              StairFormSection(
                title: 'メモ',
                icon: CupertinoIcons.pencil,
                accent: StairColors.memo,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(venue.memo),
                  ),
                ],
              ),
            StairFormSection(
              title: '参加した会',
              icon: CupertinoIcons.calendar,
              accent: StairColors.live,
              children: [
                if (visits.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('参加記録がありません'),
                  ),
                for (final event in visits)
                  CupertinoButton(
                    padding: const EdgeInsets.all(16),
                    onPressed: () => Navigator.of(context).push<void>(
                      CupertinoPageRoute(
                        builder: (_) =>
                            EventDetailScreen(store: store, eventId: event.id),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        event.title,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class VenueEditorScreen extends StatefulWidget {
  const VenueEditorScreen({super.key, required this.store, this.venue});
  final GiriStore store;
  final GiriVenue? venue;
  @override
  State<VenueEditorScreen> createState() => _VenueEditorScreenState();
}

class _VenueEditorScreenState extends State<VenueEditorScreen> {
  late final _name = TextEditingController(text: widget.venue?.name ?? '');
  late String _prefecture = widget.venue?.prefecture ?? '';
  late final _map = TextEditingController(text: widget.venue?.mapUrl ?? '');
  late final _memo = TextEditingController(text: widget.venue?.memo ?? '');
  late double? _latitude = widget.venue?.latitude;
  late double? _longitude = widget.venue?.longitude;
  late String _address = widget.venue?.mapAddress ?? '';
  bool _saving = false;
  bool _choosingMap = false;

  @override
  void dispose() {
    for (final field in [_name, _map, _memo]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseMap() async {
    if (_saving || _choosingMap) return;
    setState(() => _choosingMap = true);
    try {
      final place = await StairMaps.pickPlace(
        initialQuery: '$_prefecture ${_name.text}'.trim(),
        dark: Theme.of(context).brightness == Brightness.dark,
      );
      if (place == null || !mounted) return;
      setState(() {
        if (_name.text.trim().isEmpty) _name.text = place.name;
        _latitude = place.latitude;
        _longitude = place.longitude;
        _address = place.address;
        final prefecture = japanesePrefectures
            .where(place.address.contains)
            .firstOrNull;
        if (_prefecture.isEmpty && prefecture != null) _prefecture = prefecture;
      });
    } catch (_) {
      if (mounted) showStairMessage(context, '地図を読み込めませんでした。', error: true);
    } finally {
      if (mounted) setState(() => _choosingMap = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _saving || _choosingMap) return;
    final map = Uri.tryParse(_map.text.trim());
    if (_map.text.trim().isNotEmpty &&
        (map == null ||
            !['http', 'https'].contains(map.scheme) ||
            map.host.isEmpty)) {
      showStairMessage(context, '地図のURLを確認してください。', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.saveVenue(
        GiriVenue(
          id: widget.venue?.id ?? widget.store.newId(),
          name: _name.text.trim(),
          prefecture: _prefecture,
          mapUrl: _map.text.trim(),
          memo: _memo.text,
          latitude: _latitude,
          longitude: _longitude,
          mapAddress: _address,
        ),
      );
      if (!mounted) return;
      final saved = widget.store.venueDirectory
          .where(
            (venue) =>
                playerSearchKey(venue.name) == playerSearchKey(_name.text),
          )
          .firstOrNull;
      StairNativeControls.saveFeedback();
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) {
        showStairMessage(
          context,
          error is FormatException ? error.message : '会場を保存できませんでした。',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StairCupertinoAlertDialog(
        title: const Text('会場の登録情報を削除しますか？'),
        content: const Text('過去の会に記録した会場名は残ります。'),
        actions: [
          StairCupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          StairCupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.store.deleteVenue(widget.venue!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showStairMessage(context, '削除できませんでした。', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(
      title: Text(widget.venue == null ? '会場を追加' : '会場を編集'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ValueListenableBuilder(
            valueListenable: _name,
            builder: (context, value, _) => StairSaveButton(
              onPressed: _saving || _choosingMap || value.text.trim().isEmpty
                  ? null
                  : _save,
              saving: _saving,
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        StairFormSection(
          title: '会場情報',
          icon: CupertinoIcons.placemark,
          accent: StairColors.venue,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('venue-name'),
                controller: _name,
                enabled: !_saving,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: '会場名 *'),
              ),
            ),
            StairMenuRow<String>(
              label: '都道府県',
              value: _prefecture,
              accent: StairColors.venue,
              items: {
                '': '未設定',
                for (final prefecture in japanesePrefectures)
                  prefecture: prefecture,
                if (_prefecture.isNotEmpty &&
                    !japanesePrefectures.contains(_prefecture))
                  _prefecture: _prefecture,
              },
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _prefecture = value),
            ),
          ],
        ),
        StairFormSection(
          title: 'マップ',
          icon: CupertinoIcons.map,
          accent: StairColors.venue,
          children: [
            if (_latitude != null && _longitude != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: StairMapPreview(
                  latitude: _latitude!,
                  longitude: _longitude!,
                  name: _name.text,
                ),
              ),
            if (_address.isNotEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(_address)),
            if (StairMaps.available)
              CupertinoButton(
                key: const ValueKey('venue-map-select'),
                onPressed: _saving || _choosingMap ? null : _chooseMap,
                child: _choosingMap
                    ? const CupertinoActivityIndicator()
                    : Text(_latitude == null ? 'マップから登録' : 'マップを変更'),
              ),
            if (_latitude != null || _longitude != null)
              CupertinoButton(
                onPressed: _saving || _choosingMap
                    ? null
                    : () => setState(() {
                        _latitude = null;
                        _longitude = null;
                        _address = '';
                      }),
                child: const Text('マップの登録を解除'),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _map,
                enabled: !_saving,
                maxLines: 1,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'マップのURL'),
              ),
            ),
          ],
        ),
        StairFormSection(
          title: 'メモ',
          icon: CupertinoIcons.pencil,
          accent: StairColors.memo,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _memo,
                enabled: !_saving,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(hintText: '会場についてのメモ'),
              ),
            ),
          ],
        ),
        if (widget.venue != null && !widget.venue!.id.startsWith('history:'))
          CupertinoButton(
            onPressed: _saving || _choosingMap ? null : _delete,
            child: const Text('登録情報を削除'),
          ),
      ],
    ),
  );
}
