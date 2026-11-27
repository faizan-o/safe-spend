import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Phone-sized, tablet/small-window and desktop-sized layouts.
enum ScreenSize { compact, medium, expanded }

class Responsive {
  const Responsive._();

  /// Below this width the app uses a bottom navigation bar (phones).
  static const double mediumBreakpoint = 720;

  /// From this width the navigation rail shows labels (desktop windows).
  static const double expandedBreakpoint = 1100;

  /// The dashboard shows two columns from this content width.
  static const double twoColumnBreakpoint = 880;

  static ScreenSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= expandedBreakpoint) return ScreenSize.expanded;
    if (width >= mediumBreakpoint) return ScreenSize.medium;
    return ScreenSize.compact;
  }

  /// True when the window is wide enough for the side navigation rail.
  static bool isWide(BuildContext context) => of(context) != ScreenSize.compact;

  /// List padding that keeps content at most [maxWidth] wide and centered,
  /// while the scrollbar stays at the window edge (as desktop apps do).
  static EdgeInsets listPadding(
    BuildContext context, {
    double maxWidth = 720,
    double side = 16,
    double top = 0,
    double bottom = 24,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final extra = math.max(0.0, (width - maxWidth) / 2);
    final horizontal = math.max(side, extra);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }
}

/// Centers [child] and limits its width on large screens.
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
