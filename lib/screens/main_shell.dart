import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/responsive.dart';
import 'dashboard_screen.dart';
import 'receipts_screen.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';

/// The signed-in app: three tabs, Voice (the first screen), Dashboard and Receipts.
/// All stay alive when switching, so nothing reloads or is lost.
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.auth,
    required this.user,
    required this.data,
  });

  final AuthService auth;
  final AuthUser user;
  final UserData data;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const int _voiceTab = 0;
  static const int _dashboardTab = 1;

  final GlobalKey<VoiceScreenState> _voiceKey = GlobalKey<VoiceScreenState>();

  int _index = _voiceTab;

  void _go(int index) {
    if (index == _index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }

  /// Opens the Voice tab and starts the camera/gallery choice for a receipt.
  void _scan() {
    _go(_voiceTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _voiceKey.currentState?.scanReceipt());
  }

  @override
  Widget build(BuildContext context) {
    final size = Responsive.of(context);
    final wide = size != ScreenSize.compact;

    final pages = IndexedStack(
      index: _index,
      children: [
        VoiceScreen(
          key: _voiceKey,
          auth: widget.auth,
          user: widget.user,
          data: widget.data,
          isActive: _index == _voiceTab,
          // On wide screens the side navigation already has a Dashboard entry.
          onOpenDashboard: wide ? null : () => _go(_dashboardTab),
        ),
        DashboardScreen(
          auth: widget.auth,
          user: widget.user,
          data: widget.data,
          onOpenVoice: wide ? null : () => _go(_voiceTab),
        ),
        ReceiptsScreen(data: widget.data, onScan: _scan),
      ],
    );

    if (!wide) {
      // Phones: bottom navigation bar.
      return Scaffold(
        body: pages,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: 'Voice'),
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Receipts'),
          ],
        ),
      );
    }

    // Tablets, desktop and web: navigation rail on the left.
    final extended = size == ScreenSize.expanded;
    final railWidth = extended ? 232.0 : 88.0;
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: railWidth,
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: railWidth,
              selectedIndex: _index,
              onDestinationSelected: _go,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: SizedBox(
                height: 68, // same height as the page title bars, so the two line up
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.savings_outlined, color: theme.colorScheme.primary, size: 28),
                    if (extended) ...[
                      const SizedBox(width: 10),
                      Text(AppConfig.appName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RailAction(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          extended: extended,
                          onTap: () => openSettings(context, widget.auth, widget.user),
                        ),
                        _RailAction(
                          icon: Icons.logout,
                          label: 'Sign out',
                          extended: extended,
                          onTap: () => unawaited(widget.auth.signOut()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: Text('Voice')),
                NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Dashboard')),
                NavigationRailDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: Text('Receipts')),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            // Pages size themselves to the space beside the rail.
            child: MediaQuery(
              data: media.copyWith(size: Size(media.size.width - railWidth - 1, media.size.height)),
              child: pages,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({required this.icon, required this.label, required this.extended, required this.onTap});

  final IconData icon;
  final String label;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!extended) return IconButton(tooltip: label, icon: Icon(icon), onPressed: onTap);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
