import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/app_logo.dart';

import '../data/user_data.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/responsive.dart';
import '../logic/dashboard_controller.dart';
import '../notifications/notification_coordinator.dart';
import '../notifications/notification_service.dart';
import '../notifications/reminder_planner.dart';
import 'bills_screen.dart';
import 'dashboard_screen.dart';
import 'debts_screen.dart';
import 'receipts_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';

/// The signed-in app: six tabs, Voice (the first screen), Dashboard, Bills,
/// Debts, Receipts and the Expense report. One shared controller feeds Dashboard, Bills and Debts.
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
  static const int _debtsTab = 3;
  static const int _reportTab = 5;

  final GlobalKey<VoiceScreenState> _voiceKey = GlobalKey<VoiceScreenState>();

  late final DashboardController _controller = DashboardController(widget.data);

  late final NotificationCoordinator _notifications = NotificationCoordinator(_controller);
  StreamSubscription<String>? _taps;

  int _index = _voiceTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recordDueItems();
    _notifications.start();
    final service = NotificationService.instance;
    _taps = service.taps.listen(_openFromNotification);
    // The app was opened by tapping a notification while it was closed.
    service.init().then((_) {
      final payload = service.launchPayload;
      service.launchPayload = null;
      if (payload != null && mounted) _openFromNotification(payload);
    });
  }

  /// Takes the user to the screen a tapped notification is about.
  void _openFromNotification(String payload) {
    if (!mounted) return;
    switch (payload) {
      case ReminderPayload.daily:
        _go(_voiceTab);
      case ReminderPayload.bills:
        _go(_billsTab);
      case ReminderPayload.debts:
        _go(_debtsTab);
      case ReminderPayload.budget:
        _go(_dashboardTab);
    }
  }

  @override
  void dispose() {
    unawaited(_taps?.cancel());
    _notifications.dispose();
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
    _notifications.refresh(force: true);
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

  void _openReceipts() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => ReceiptsScreen(
          data: widget.data,
          onScan: () {
            Navigator.of(routeContext).pop();
            _scan();
          },
        ),
      ),
    );
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
          // Phones have no Receipts tab; it opens from the Dashboard menu.
          onOpenReceipts: wide ? null : _openReceipts,
        ),
        BillsScreen(controller: _controller, data: widget.data),
        DebtsScreen(controller: _controller, data: widget.data),
        ReceiptsScreen(data: widget.data, onScan: _scan),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => ReportScreen(
            auth: widget.auth,
            user: widget.user,
            data: widget.data,
            symbol: _controller.symbol,
          ),
        ),
      ],
    );

    if (!wide) {
      // Phones: Voice is the big round button in the middle, raised above the
      // bar; Dashboard, Bills, Debts and Report sit in the bar, two each side.
      final scheme = Theme.of(context).colorScheme;
      final voiceSelected = _index == _voiceTab;
      return Scaffold(
        body: pages,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: Semantics(
          label: 'Voice',
          child: SizedBox(
            width: 68,
            height: 68,
            child: FloatingActionButton(
              heroTag: 'voice-tab',
              elevation: 4,
              shape: const CircleBorder(),
              backgroundColor: voiceSelected ? scheme.primary : scheme.primaryContainer,
              foregroundColor: voiceSelected ? scheme.onPrimary : scheme.onPrimaryContainer,
              onPressed: () => _go(_voiceTab),
              child: Icon(voiceSelected ? Icons.mic : Icons.mic_none, size: 34),
            ),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 68,
          padding: EdgeInsets.zero,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: Row(
            children: [
              _BarItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard', selected: _index == _dashboardTab, onTap: () => _go(_dashboardTab)),
              _BarItem(icon: Icons.event_note_outlined, selectedIcon: Icons.event_note, label: 'Bills', selected: _index == _billsTab, onTap: () => _go(_billsTab)),
              // The gap under the round button, with its label.
              SizedBox(
                width: 84,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Voice',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: voiceSelected ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: voiceSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                  ),
                ),
              ),
              _BarItem(icon: Icons.handshake_outlined, selectedIcon: Icons.handshake, label: 'Debts', selected: _index == _debtsTab, onTap: () => _go(_debtsTab)),
              _BarItem(icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'Report', selected: _index == _reportTab, onTap: () => _go(_reportTab)),
            ],
          ),
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
                NavigationRailDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: Text('Report')),
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

/// One of the four tabs in the phone's bottom bar.
class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
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
