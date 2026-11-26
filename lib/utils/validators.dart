/// Form field validators. Each returns an error message, or null when valid.
class Validators {
  const Validators._();

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _letter = RegExp(r'[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Rules for choosing a new password (sign up).
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!_letter.hasMatch(v) || !_digit.hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// Sign in only checks that something was typed; the server decides.
  static String? existingPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    return null;
  }

  /// Confirm-password validator. [original] returns the first password field's text.
  static String? Function(String?) matches(String Function() original) {
    return (value) {
      if (value == null || value.isEmpty) return 'Confirm your password';
      if (value != original()) return "Passwords don't match";
      return null;
    };
  }
}
