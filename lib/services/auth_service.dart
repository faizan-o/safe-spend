/// A signed-in user, independent of any backend.
class AuthUser {
  const AuthUser({required this.uid, required this.email, this.displayName});

  final String uid;
  final String email;
  final String? displayName;

  /// First name for greetings; falls back to the part of the email before "@".
  String get firstName {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return email.split('@').first;
    return name.split(RegExp(r'\s+')).first;
  }
}

/// An error whose [message] is safe to show directly to the user.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the UI needs from authentication. Screens depend on this interface,
/// so the backend (Firebase or the local demo) can be swapped without UI changes.
abstract class AuthService {
  /// True when running on the on-device demo backend instead of Firebase.
  bool get isDemo;

  /// Whether "Continue with Google" works with this backend.
  bool get supportsGoogle;

  AuthUser? get currentUser;

  /// Emits the current user (or null) immediately, then on every change.
  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<AuthUser> signIn({required String email, required String password});

  /// Signs in (or creates the account) with Google.
  /// Returns null when the user closes the Google screen without choosing.
  Future<AuthUser?> signInWithGoogle();

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}
