import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts normal addresses', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('  first.last@mail.example.com '), isNull);
    });

    test('rejects empty and malformed addresses', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
      expect(Validators.email('no-at-sign'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('a b@c.com'), isNotNull);
    });
  });

  group('Validators.newPassword', () {
    test('requires 8+ characters with a letter and a number', () {
      expect(Validators.newPassword('abc12345'), isNull);
      expect(Validators.newPassword('short1'), isNotNull);
      expect(Validators.newPassword('allletters'), isNotNull);
      expect(Validators.newPassword('12345678'), isNotNull);
      expect(Validators.newPassword(''), isNotNull);
    });
  });

  group('Validators.matches', () {
    test('compares against the original password', () {
      final validate = Validators.matches(() => 'abc12345');
      expect(validate('abc12345'), isNull);
      expect(validate('abc12346'), isNotNull);
      expect(validate(''), isNotNull);
    });
  });

  group('Validators.name', () {
    test('needs at least two characters', () {
      expect(Validators.name('Al'), isNull);
      expect(Validators.name('A'), isNotNull);
      expect(Validators.name('   '), isNotNull);
    });
  });
}
