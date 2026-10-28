import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SF Symbols have weight-specific artwork. A fixed Cupertino icon font does
/// not reproduce `.system(size: 14, weight: .semibold)` from LiveStair.
/// iOS supplies small transparent PNGs once at startup; Android and test
/// engines keep their normal icon font without depending on an iOS runner.
abstract final class StairSymbols {
  static const _channel = MethodChannel('giristair/native-symbols');
  static final _images = <String, _StairSymbolImage>{};

  // Aliases (add/plus, info/info_circle, location/placemark) share IconData,
  // so keep a single key for each glyph.
  static final _names = <IconData, String>{
    CupertinoIcons.add: 'plus',
    CupertinoIcons.clock: 'clock',
    CupertinoIcons.slider_horizontal_3: 'slider.horizontal.3',
    CupertinoIcons.person: 'person',
    CupertinoIcons.person_2: 'person.2',
    CupertinoIcons.person_crop_circle: 'person.crop.circle',
    CupertinoIcons.rosette: 'rosette',
    CupertinoIcons.calendar: 'calendar',
    CupertinoIcons.globe: 'globe',
    CupertinoIcons.pencil: 'pencil',
    CupertinoIcons.text_alignleft: 'text.alignleft',
    CupertinoIcons.square_list: 'list.bullet.rectangle',
    CupertinoIcons.list_number: 'list.number',
    CupertinoIcons.placemark: 'mappin.and.ellipse',
    CupertinoIcons.doc_text: 'doc.text',
    CupertinoIcons.doc_text_viewfinder: 'doc.text.viewfinder',
    CupertinoIcons.doc_on_clipboard: 'doc.on.clipboard',
    CupertinoIcons.photo_on_rectangle: 'photo.on.rectangle',
    CupertinoIcons.lightbulb: 'lightbulb',
    CupertinoIcons.link: 'link',
    CupertinoIcons.bell: 'bell',
    CupertinoIcons.tray: 'tray',
    CupertinoIcons.share: 'square.and.arrow.up',
    CupertinoIcons.chart_bar: 'chart.bar',
    CupertinoIcons.chat_bubble: 'bubble.left',
    CupertinoIcons.question_circle: 'questionmark.circle',
    CupertinoIcons.info_circle: 'info.circle',
    CupertinoIcons.gear_solid: 'gearshape.fill',
    CupertinoIcons.check_mark_circled: 'checkmark.circle',
    CupertinoIcons.check_mark_circled_solid: 'checkmark.circle.fill',
    CupertinoIcons.plus_circle: 'plus.circle',
    CupertinoIcons.minus_circle: 'minus.circle',
  };

  static String? nameFor(IconData icon) => _names[icon];

  static Future<void> initialize({double? scale}) async {
    _images.clear();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final views = PlatformDispatcher.instance.views;
    final displayScale =
        scale ?? (views.isEmpty ? 2 : views.first.devicePixelRatio);
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'rasterize',
        {'symbols': _names.values.toSet().toList(), 'scale': displayScale},
      );
      if (response == null) return;
      for (final entry in response.entries) {
        final image = _StairSymbolImage.decode(entry.value);
        if (image != null) _images[entry.key] = image;
      }
    } on MissingPluginException {
      // A widget-test engine or an older runner can still draw every icon.
    } on PlatformException {
      // Keep the Flutter icon if UIKit cannot rasterize a symbol.
    }
  }

  static _StairSymbolImage? _image(
    IconData icon,
    double size,
    FontWeight weight,
  ) {
    final name = nameFor(icon);
    if (name == null || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return _images['$name/${size.toInt()}/${weight.value.toInt()}'];
  }
}

class _StairSymbolImage {
  const _StairSymbolImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final double width;
  final double height;

  static _StairSymbolImage? decode(Object? value) {
    if (value is! Map) return null;
    final bytes = value['bytes'];
    final width = value['width'];
    final height = value['height'];
    if (bytes is! Uint8List ||
        bytes.isEmpty ||
        width is! num ||
        height is! num) {
      return null;
    }
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return null;
    }
    return _StairSymbolImage(bytes, width.toDouble(), height.toDouble());
  }
}

class StairSymbolIcon extends StatelessWidget {
  const StairSymbolIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.weight,
    required this.color,
  });

  final IconData icon;
  final double size;
  final FontWeight weight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final image = StairSymbols._image(icon, size, weight);
    if (image == null) return Icon(icon, size: size, color: color);
    return Center(
      child: Image.memory(
        image.bytes,
        width: image.width,
        height: image.height,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
