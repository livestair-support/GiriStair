import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'stair_typography.dart';

/// Only enabled after the iOS runner confirms that its view factories exist.
/// Widget tests and Android retain the Flutter controls without plugin calls.
abstract final class StairNativeControls {
  static const _channel = MethodChannel('giristair/native-controls');
  static bool available = false;

  static Future<void> initialize() async {
    available = false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'initialize',
      );
      available = response?['available'] == true;
      final fonts = response?['fonts'];
      if (fonts is Map) {
        StairTypography.configureNativeFonts(Map<String, dynamic>.from(fonts));
      }
    } on MissingPluginException {
      // A test engine or an older runner has no native controls registered.
    } on PlatformException {
      // The Flutter fallback remains usable if the native presenter is absent.
    }
  }

  static Future<StairNativeDateSelection?> pickDate({
    required String label,
    required DateTime initial,
    required String mode,
    required bool dark,
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'pickDate',
      {
        'label': label,
        'mode': mode,
        'dark': dark,
        'components': [
          initial.year,
          initial.month,
          initial.day,
          initial.hour,
          initial.minute,
        ],
      },
    );
    if (response?['committed'] != true) return null;
    final parts = response?['components'];
    if (parts == null) return const StairNativeDateSelection(null);
    if (parts is! List ||
        parts.length != 5 ||
        parts.any((part) => part is! int)) {
      throw const FormatException('Invalid native date selection.');
    }
    return StairNativeDateSelection(
      DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]),
    );
  }

  static Future<void> saveFeedback() async {
    if (available) {
      await _channel.invokeMethod<void>('saveFeedback');
    } else {
      await HapticFeedback.lightImpact();
    }
  }
}

class StairNativeDateSelection {
  const StairNativeDateSelection(this.value);
  final DateTime? value;
}

/// The actual iOS menu button owns its gesture and menu lifecycle. Dismissal
/// does not send a selection, avoiding a synthetic dialog or pending Future.
class StairNativeMenu extends StatefulWidget {
  const StairNativeMenu({
    super.key,
    required this.label,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool enabled;

  @override
  State<StairNativeMenu> createState() => _StairNativeMenuState();
}

class _StairNativeMenuState extends State<StairNativeMenu> {
  MethodChannel? _channel;

  Map<String, Object> _arguments(BuildContext context) => {
    'label': widget.label,
    'labels': widget.labels,
    'selectedIndex': widget.selectedIndex,
    'enabled': widget.enabled,
    'dark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
    'textScale': MediaQuery.textScalerOf(context).scale(17) / 17,
  };

  void _created(int id) {
    _channel = MethodChannel('giristair/native-menu/$id');
    _channel!.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'opened') {
        FocusManager.instance.primaryFocus?.unfocus();
      } else if (call.method == 'selected' && call.arguments is int) {
        final index = call.arguments as int;
        if (widget.enabled &&
            index >= 0 &&
            index < widget.labels.length &&
            index != widget.selectedIndex) {
          widget.onSelected(index);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant StairNativeMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  void _update() {
    final channel = _channel;
    if (channel != null) {
      unawaited(channel.invokeMethod<void>('update', _arguments(context)));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.selectedIndex >= 0 && widget.selectedIndex < widget.labels.length
        ? widget.labels[widget.selectedIndex]
        : '';
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: StairTypography.role(StairTextRole.value),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = text.width + MediaQuery.textScalerOf(context).scale(22);
    text.dispose();
    return SizedBox(
      width: width,
      height: MediaQuery.textScalerOf(context).scale(32),
      child: UiKitView(
        viewType: 'giristair/native-menu',
        creationParams: _arguments(context),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
      ),
    );
  }
}

class StairNativeTime extends StatefulWidget {
  const StairNativeTime({
    super.key,
    required this.label,
    required this.initial,
    required this.hasValue,
    this.onChanged,
  });

  final String label;
  final DateTime initial;
  final bool hasValue;
  final ValueChanged<DateTime>? onChanged;

  @override
  State<StairNativeTime> createState() => _StairNativeTimeState();
}

class _StairNativeTimeState extends State<StairNativeTime> {
  MethodChannel? _channel;

  Map<String, Object> _arguments() => {
    'label': widget.label,
    'hasValue': widget.hasValue,
    'enabled': widget.onChanged != null,
    'dark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
    'components': [
      widget.initial.year,
      widget.initial.month,
      widget.initial.day,
      widget.initial.hour,
      widget.initial.minute,
    ],
  };

  void _created(int id) {
    _channel = MethodChannel('giristair/native-time/$id');
    _channel!.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'changed' || call.arguments is! List) {
        return;
      }
      final parts = call.arguments as List;
      if (parts.length != 5 || parts.any((value) => value is! int)) return;
      widget.onChanged?.call(
        DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]),
      );
    });
  }

  @override
  void didUpdateWidget(covariant StairNativeTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  void _update() {
    if (_channel case final channel?) {
      unawaited(channel.invokeMethod<void>('update', _arguments()));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    height: 32,
    child: UiKitView(
      viewType: 'giristair/native-time',
      creationParams: _arguments(),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
    ),
  );
}
