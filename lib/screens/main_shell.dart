import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'voice_screen.dart';

/// The signed-in app: two tabs, Voice (the first screen) and Dashboard.
/// Both stay alive when switching, so nothing reloads or is lost.
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

  int _index = _voiceTab;

  void _go(int index) {
    if (index == _index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          VoiceScreen(
            auth: widget.auth,
            user: widget.user,
            data: widget.data,
            isActive: _index == _voiceTab,
            onOpenDashboard: () => _go(_dashboardTab),
          ),
          DashboardScreen(
            auth: widget.auth,
            user: widget.user,
            data: widget.data,
            onOpenVoice: () => _go(_voiceTab),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
        ],
      ),
    );
  }
}
