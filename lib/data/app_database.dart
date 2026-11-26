import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_data.dart';

/// Entry point to the database. Create one after Firebase has been
/// initialized, then ask it for the signed-in user's data.
class AppDatabase {
  AppDatabase([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Map<String, UserData> _users = {};

  /// Call once, right after Firebase.initializeApp and before any other
  /// Firestore use. Keeps a local copy of the data so the app works offline:
  /// new expenses show up immediately and sync when the connection returns.
  static void configure([FirebaseFirestore? firestore]) {
    (firestore ?? FirebaseFirestore.instance).settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  /// The data of one user. The same object is returned for the same uid.
  UserData forUser(String uid) {
    return _users.putIfAbsent(uid, () => UserData(_firestore, uid));
  }

  /// Forgets a user's cached repositories (call on sign-out).
  void forget(String uid) => _users.remove(uid);
}
