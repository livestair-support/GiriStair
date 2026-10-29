import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The supplied artwork is used as-is, without recoloring or redrawing.
abstract final class GiriBrand {
  static const icon = 'assets/brand/source/app_icon.jpg';
  static const wordmark = 'assets/brand/source/wordmark.jpg';
  static const launchScreen = 'assets/brand/source/launch_screen.jpg';
  static const background = Color(0xFFF5F1E8);
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.width = 160});
  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
    GiriBrand.wordmark,
    width: width,
    fit: BoxFit.contain,
    semanticLabel: 'GiriStair',
  );
}

class BrandLaunchScreen extends StatelessWidget {
  const BrandLaunchScreen({super.key});

  @override
  Widget build(BuildContext context) => const AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: GiriBrand.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(
      backgroundColor: GiriBrand.background,
      body: SizedBox.expand(
        child: Image(
          image: AssetImage(GiriBrand.launchScreen),
          fit: BoxFit.contain,
          semanticLabel: 'GiriStair',
        ),
      ),
    ),
  );
}
