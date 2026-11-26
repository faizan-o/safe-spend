import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

/// Reads and writes the profile document users/{uid}.
class UserRepository {
  UserRepository(this._doc);

  final DocumentReference<Map<String, dynamic>> _doc;

  Stream<UserProfile?> watchProfile() => _doc.snapshots().map(_parse);

  /// Reads the profile. With [serverOnly] it never answers from the local
  /// cache and throws when the device is offline, which is what the first-time
  /// setup uses to avoid mistaking "not cached yet" for "new user".
  Future<UserProfile?> getProfile({bool serverOnly = false}) async {
    final snapshot = await _doc.get(
      GetOptions(source: serverOnly ? Source.server : Source.serverAndCache),
    );
    return _parse(snapshot);
  }

  /// Adds the creation of the profile to [batch].
  void queueCreate(WriteBatch batch, UserProfile profile) {
    batch.set(_doc, {
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateName(String name) => _doc.update({'name': name.trim()});

  Future<void> updateCurrency({required String code, required String symbol}) {
    return _doc.update({'currencyCode': code, 'currencySymbol': symbol});
  }

  Future<void> updateReminder(ReminderSettings reminder) {
    return _doc.update({'reminder': reminder.toMap()});
  }

  Future<void> markOnboardingComplete() {
    return _doc.update({'onboardingComplete': true});
  }

  UserProfile? _parse(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return null;
    return UserProfile.fromMap(snapshot.id, data);
  }
}
