import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// On-device demo authentication, used until Firebase is configured.
///
/// Accounts live only in this app's local storage, on this device. The salted
/// SHA-256 hash is fine for trying the UI but is NOT a substitute for a real
/// backend: use [FirebaseAuthService] for anything beyond development.
class LocalAuthService implements AuthService {
  LocalAuthService._(this._prefs) {
    final email = _prefs.getString(_sessionKey);
    final record = email == null ? null : _readUsers()[email];
    if (email != null && record != null) {
      _current = _toUser(email, record as Map<String, dynamic>);
    }
  }

  static const _usersKey = 'local_auth_users';
  static const _sessionKey = 'local_auth_session';

  final SharedPreferences _prefs;
  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _current;

  static Future<LocalAuthService> create() async {
    return LocalAuthService._(await SharedPreferences.getInstance());
  }

  @override
  bool get isDemo => true;

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await _pretendToBeOnline();
    final key = _normalize(email);
    final users = _readUsers();
    if (users.containsKey(key)) {
      throw const AuthException(
        'An account with this email already exists. Try signing in instead.',
      );
    }
    final salt = _newSalt();
    users[key] = {
      'uid': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'name': name.trim(),
      'salt': salt,
      'hash': _hash(salt, password),
    };
    await _prefs.setString(_usersKey, jsonEncode(users));
    return _startSession(key, users[key] as Map<String, dynamic>);
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await _pretendToBeOnline();
    final key = _normalize(email);
    final record = _readUsers()[key] as Map<String, dynamic>?;
    if (record == null ||
        record['hash'] != _hash(record['salt'] as String, password)) {
      throw const AuthException('Incorrect email or password.');
    }
    return _startSession(key, record);
  }

  @override
  bool get supportsGoogle => false;

  @override
  Future<AuthUser?> signInWithGoogle() {
    throw const AuthException(
      'Google sign-in needs Firebase. Run flutterfire configure first.',
    );
  }

  @override
  Future<void> sendPasswordReset(String email) => _pretendToBeOnline();

  @override
  Future<String?> getIdToken() async => null;

  @override
  Future<void> signOut() async {
    await _prefs.remove(_sessionKey);
    _current = null;
    _changes.add(null);
  }

  Future<AuthUser> _startSession(String key, Map<String, dynamic> record) async {
    await _prefs.setString(_sessionKey, key);
    final user = _toUser(key, record);
    _current = user;
    _changes.add(user);
    return user;
  }

  AuthUser _toUser(String email, Map<String, dynamic> record) {
    return AuthUser(
      uid: record['uid'] as String,
      email: email,
      displayName: record['name'] as String?,
    );
  }

  Map<String, dynamic> _readUsers() {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  String _normalize(String email) => email.trim().toLowerCase();

  String _newSalt() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  String _hash(String salt, String password) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  Future<void> _pretendToBeOnline() {
    return Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
