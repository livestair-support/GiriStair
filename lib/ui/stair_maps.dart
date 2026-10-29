import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// A place chosen explicitly from Apple's map search. No location is requested.
class StairPlace {
  const StairPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;

  factory StairPlace.fromMap(Map<Object?, Object?> value) {
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (value['name'] is! String ||
        value['address'] is! String ||
        latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('地図情報を読み取れませんでした。');
    }
    return StairPlace(
      name: value['name'] as String,
      address: value['address'] as String,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}

abstract final class StairMaps {
  static const _channel = MethodChannel('giristair/native-maps');
  static bool available = false;

  static Future<void> initialize() async {
    available = false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'initialize',
      );
      available = response?['available'] == true;
    } on MissingPluginException {
      // Older runners can still register an external map URL.
    } on PlatformException {
      // The native view is not used until the runner confirms registration.
    }
  }

  static Future<StairPlace?> pickPlace({
    required String initialQuery,
    bool? dark,
  }) async {
    if (!available) await initialize();
    if (!available) return null;
    FocusManager.instance.primaryFocus?.unfocus();
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'pickPlace',
      {'initialQuery': initialQuery.trim(), if (dark != null) 'dark': dark},
    );
    if (response == null) return null;
    return StairPlace.fromMap(response);
  }
}

/// LiveStair uses a 190pt venue map, with a 0.005-degree region and 16pt corners.
class StairMapPreview extends StatefulWidget {
  const StairMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.name,
    this.height = 190,
    this.onTap,
  });

  final double latitude;
  final double longitude;
  final String name;
  final double height;
  final VoidCallback? onTap;

  @override
  State<StairMapPreview> createState() => _StairMapPreviewState();
}

class _StairMapPreviewState extends State<StairMapPreview> {
  MethodChannel? _channel;

  Map<String, Object> _arguments() => {
    'latitude': widget.latitude,
    'longitude': widget.longitude,
    'name': widget.name,
    'dark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant StairMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    if (_channel case final channel?) {
      unawaited(channel.invokeMethod<void>('configure', _arguments()));
    }
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('giristair/native-map/$id');
    _update();
  }

  Future<void> _openExternal() async {
    final coordinates = '${widget.latitude},${widget.longitude}';
    final uri = defaultTargetPlatform == TargetPlatform.iOS
        ? Uri.https('maps.apple.com', '/', {
            'll': coordinates,
            'q': widget.name,
          })
        : Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': coordinates,
          });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final native =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        StairMaps.available;
    final onTap = widget.onTap ?? () => unawaited(_openExternal());
    return Semantics(
      button: true,
      label: '${widget.name}の地図を開く',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: widget.height,
          child: native
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: UiKitView(
                    viewType: 'giristair/native-map',
                    creationParams: _arguments(),
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: _created,
                  ),
                )
              : CupertinoButton(
                  onPressed: onTap,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.map),
                      SizedBox(width: 8),
                      Text('地図を開く'),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
