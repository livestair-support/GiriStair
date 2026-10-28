import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stair_theme.dart';

/// LiveStair uses SwiftUI's system TabView, with no custom selection capsule.
/// On iPhone, let the same iOS tab-bar implementation own its geometry, fonts,
/// symbols, glass, selection background and animation. Flutter retains the
/// screen state and receives only the selected index.
class StairTabBar extends StatefulWidget {
  const StairTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.nativeAvailable = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool nativeAvailable;

  @override
  State<StairTabBar> createState() => _StairTabBarState();
}

class _StairTabBarState extends State<StairTabBar> {
  static const _viewType = 'giristair/native-tab-bar';
  MethodChannel? _channel;
  double? _nativeHeight;
  Map<String, Object>? _configuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant StairTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  Map<String, Object> _arguments() => {
    'selectedIndex': widget.currentIndex,
    'dark': Theme.of(context).brightness == Brightness.dark,
    'tintColor': StairColors.action.toARGB32(),
  };

  void _configure() {
    final channel = _channel;
    if (channel == null) return;
    final arguments = _arguments();
    if (mapEquals(_configuration, arguments)) return;
    _configuration = arguments;
    unawaited(channel.invokeMethod<void>('configure', arguments));
  }

  void _created(int id) {
    final channel = MethodChannel('$_viewType/$id');
    _channel = channel;
    _configuration = null;
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'select') {
        final index = call.arguments;
        if (index is int && index >= 0 && index < 5) widget.onTap(index);
      } else if (call.method == 'heightChanged') {
        final height = call.arguments;
        if (height is num && height >= 44 && height <= 180) {
          final measured = height.toDouble();
          if (_nativeHeight == null || (_nativeHeight! - measured).abs() > .5) {
            setState(() => _nativeHeight = measured);
          }
        }
      }
    });
    _configure();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Native iPad tabs can move to the top. Keep five bottom tabs on wider
    // layouts with Flutter's standard Cupertino control.
    final nativePhone = widget.nativeAvailable &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        MediaQuery.sizeOf(context).shortestSide < 600;
    if (nativePhone) {
      return SizedBox(
        height: _nativeHeight ?? 49 + MediaQuery.paddingOf(context).bottom,
        child: UiKitView(
          key: const ValueKey('stair-system-tab-bar'),
          viewType: _viewType,
          creationParams: _arguments(),
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
        ),
      );
    }
    return CupertinoTabBar(
      currentIndex: widget.currentIndex,
      onTap: widget.onTap,
      activeColor: StairColors.action,
      inactiveColor: Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(context).colorScheme.surface.withValues(
        alpha: .9,
      ),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.add_circled_solid),
          label: '登録',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.clock_fill),
          label: '一覧',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.emoji_events),
          label: '戦績',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.text_badge_checkmark),
          label: '思考',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.gear_solid),
          label: '設定',
        ),
      ],
    );
  }
}
