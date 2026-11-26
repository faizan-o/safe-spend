import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'auth_service.dart';

/// Real authentication backed by Firebase Authentication (email and password).
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([fb.FirebaseAuth? auth])
      : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  @override
  bool get isDemo => false;

  AuthUser? _toUser(fb.User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
    );
  }

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _auth.userChanges().map(_toUser);

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final created = credential.user;
      await created?.updateDisplayName(name.trim());
      await created?.reload();
      return _toUser(_auth.currentUser ?? created)!;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e.code));
    }
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _toUser(credential.user)!;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e.code));
    }
  }

  @override
  bool get supportsGoogle => true;

  @override
  Future<AuthUser?> signInWithGoogle() async {
    try {
      final provider = fb.GoogleAuthProvider()..addScope('email');
      final credential = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
      final user = _toUser(credential.user);
      if (user == null) {
        throw const AuthException('Google sign-in failed. Please try again.');
      }
      return user;
    } on fb.FirebaseAuthException catch (e) {
      const cancelled = {
        'canceled',
        'cancelled',
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'web-context-cancelled',
      };
      if (cancelled.contains(e.code)) return null;
      throw AuthException(_messageFor(e.code));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      // "user-not-found" is deliberately not reported, so the screen cannot be
      // used to discover which emails have accounts.
      if (e.code == 'user-not-found') return;
      throw AuthException(_messageFor(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  String _messageFor(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in instead.';
      case 'invalid-email':
        return "That email address doesn't look right.";
      case 'weak-password':
        return 'Choose a stronger password (at least 8 characters).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'account-exists-with-different-credential':
        return 'This email is already registered with a password. '
            'Sign in with your email and password instead.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled for this project yet.';
      default:
        return 'Something went wrong ($code). Please try again.';
    }
  }
}
