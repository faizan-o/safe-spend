import 'package:flutter/material.dart';

/// The SafeSpend logo (a shield with a coin and a check mark).
/// [badge] draws it on its rounded navy tile, like the app icon.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.badge = false});

  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      badge ? 'assets/logo/logo_badge.png' : 'assets/logo/logo_mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'SafeSpend logo',
    );
  }
}
