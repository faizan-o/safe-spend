/// Money helpers.
///
/// All amounts in the database are whole numbers in **minor units** (paisa for
/// PKR: 100 paisa = Rs. 1). Integers avoid the rounding errors of doubles and
/// make Firestore increments exact. Convert only at the edges: parse what the
/// user types or says, and format what is shown.
class Money {
  const Money._();

  static const int minorPerMajor = 100;

  static int fromMajor(num major) => (major * minorPerMajor).round();

  static double toMajor(int minor) => minor / minorPerMajor;

  /// Parses text such as "1,250.50", "Rs. 500" or "500". Returns minor units,
  /// or null when no valid non-negative number is found.
  static int? parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return fromMajor(value);
  }

  /// Formats minor units for display, e.g. 125050 -> "Rs. 1,251"
  /// (or "Rs. 1,250.50" with [showDecimals]).
  static String format(
    int minor, {
    String symbol = 'Rs.',
    bool showDecimals = false,
  }) {
    final negative = minor < 0;
    final abs = minor.abs();
    final String body;
    if (showDecimals) {
      final paisa = (abs % minorPerMajor).toString().padLeft(2, '0');
      body = '${_group(abs ~/ minorPerMajor)}.$paisa';
    } else {
      body = _group((abs / minorPerMajor).round());
    }
    return '${negative ? '-' : ''}$symbol $body';
  }

  static String _group(int whole) {
    final digits = whole.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
