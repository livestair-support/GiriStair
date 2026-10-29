import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'stair_native_controls.dart';

/// Toolbar actions have 44pt available; vertical padding must not clip labels.
class StairBarButton extends StatelessWidget {
  const StairBarButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    child: child,
  );
}

class StairBackButton extends StatelessWidget {
  const StairBackButton({super.key, this.onPressed, this.enabled = true});
  final VoidCallback? onPressed;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    void back() {
      if (!enabled) return;
      if (onPressed != null) {
        onPressed!();
      } else {
        Navigator.of(context).maybePop();
      }
    }

    if (StairNativeControls.available &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _SystemBack(onPressed: back, enabled: enabled);
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: enabled ? back : null,
      child: Icon(
        CupertinoIcons.back,
        size: 28,
        color: enabled
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).disabledColor,
        semanticLabel: '戻る',
      ),
    );
  }
}

class _SystemBack extends StatefulWidget {
  const _SystemBack({required this.onPressed, required this.enabled});
  final VoidCallback onPressed;
  final bool enabled;
  @override
  State<_SystemBack> createState() => _SystemBackState();
}

class _SystemBackState extends State<_SystemBack> {
  MethodChannel? _channel;
  Map<String, Object> get _values => {
    'dark': Theme.of(context).brightness == Brightness.dark,
    'enabled': widget.enabled,
  };
  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('giristair/native-back/$id');
    _channel!.setMethodCallHandler((call) async {
      if (mounted && widget.enabled && call.method == 'back') {
        widget.onPressed();
      }
    });
    unawaited(_channel!.invokeMethod<void>('configure', _values));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_channel != null) {
      unawaited(_channel!.invokeMethod<void>('configure', _values));
    }
  }

  @override
  void didUpdateWidget(covariant _SystemBack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_channel != null) {
      unawaited(_channel!.invokeMethod<void>('configure', _values));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 44,
    child: UiKitView(
      viewType: 'giristair/native-back',
      creationParams: _values,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
    ),
  );
}

/// All secondary pages use this bar, including pages added in future changes.
class StairNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  const StairNavigationBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.backgroundColor,
    this.foregroundColor,
    this.bottom,
    this.toolbarHeight = 44,
    this.leadingWidth = 64,
    this.titleSpacing,
    this.elevation,
    this.scrolledUnderElevation,
  });
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final double leadingWidth;
  final double? titleSpacing;
  final double? elevation;
  final double? scrolledUnderElevation;
  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    actions: actions,
    leading:
        leading ??
        (automaticallyImplyLeading && (ModalRoute.of(context)?.canPop ?? false)
            ? const StairBackButton()
            : null),
    automaticallyImplyLeading: false,
    leadingWidth: leadingWidth,
    titleSpacing: titleSpacing,
    centerTitle: centerTitle,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    bottom: bottom,
    toolbarHeight: toolbarHeight,
    elevation: elevation,
    scrolledUnderElevation: scrolledUnderElevation,
  );
}
