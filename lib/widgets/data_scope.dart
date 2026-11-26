import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/user_data.dart';
import '../services/auth_service.dart';

/// Makes the signed-in user's [UserData] available to every screen below it:
/// `DataScope.of(context).expenses`. The value is null in demo mode, where
/// there is no Firestore.
class DataScope extends InheritedWidget {
  const DataScope({super.key, required this.data, required super.child});

  final UserData? data;

  static UserData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DataScope>()?.data;
  }

  static UserData of(BuildContext context) {
    final data = maybeOf(context);
    assert(data != null, 'No database: the app is running in demo mode.');
    return data!;
  }

  @override
  bool updateShouldNotify(DataScope oldWidget) => oldWidget.data != data;
}

/// Wraps the signed-in part of the app. It opens the user's data, runs the
/// first-time setup (profile and default categories) and provides a
/// [DataScope] to the screens below.
class SessionBootstrap extends StatefulWidget {
  const SessionBootstrap({
    super.key,
    required this.database,
    required this.user,
    required this.child,
  });

  final AppDatabase? database;
  final AuthUser user;
  final Widget child;

  @override
  State<SessionBootstrap> createState() => _SessionBootstrapState();
}

class _SessionBootstrapState extends State<SessionBootstrap> {
  late final UserData? _data = widget.database?.forUser(widget.user.uid);

  @override
  void initState() {
    super.initState();
    _runSetup();
  }

  Future<void> _runSetup() async {
    try {
      await _data?.ensureReady(widget.user);
    } catch (error) {
      debugPrint('First-time setup failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataScope(data: _data, child: widget.child);
  }
}
