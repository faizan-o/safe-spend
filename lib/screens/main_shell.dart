import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/app_logo.dart';

import '../data/user_data.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/responsive.dart';
import '../logic/dashboard_controller.dart';
import 'bills_screen.dart';
import 'dashboard_screen.dart';
import 'debts_screen.dart';
import 'receipts_screen.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';

/// The signed-in app: five tabs, Voice (the first screen), Dashboard, Bills,
/// Debts and Receipts. One shared controller feeds Dashboard, Bills and Debts.
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

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const int _voiceTab = 0;
  static const int _dashboardTab = 1;
  static const int _billsTab = 2;

  final GlobalKey<VoiceScreenState> _voiceKey = GlobalKey<VoiceScreenState>();

  late final DashboardController _controller = DashboardController(widget.data);

  int _index = _voiceTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recordDueItems();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// When the app comes back (maybe the next day), move to today's budget and
  /// record any automatic bills that have come due.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _controller.refreshToday();
    _recordDueItems();
  }

  /// Bills set to "record automatically" are added once their date arrives.
  void _recordDueItems() {
    widget.data.recurring.recordDue().then((_) {}, onError: (Object _) {});
  }

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
          controller: _controller,
          onOpenVoice: wide ? null : () => _go(_voiceTab),
          onOpenBills: () => _go(_billsTab),
        ),
        BillsScreen(controller: _controller, data: widget.data),
        DebtsScreen(controller: _controller, data: widget.data),
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
            NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Bills'),
            NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'Debts'),
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
                    const AppLogo(size: 34),
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
                          onTap: () => openSettings(context, widget.auth, widget.user, data: widget.data),
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
                NavigationRailDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: Text('Bills')),
                NavigationRailDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: Text('Debts')),
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
