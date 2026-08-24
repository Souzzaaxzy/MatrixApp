import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/validators.dart';

void main() {
  group('Validators.name', () {
    test('rejects empty', () {
      expect(Validators.name(''), isNotNull);
      expect(Validators.name('  '), isNotNull);
    });
    test('rejects too short', () {
      expect(Validators.name('A'), isNotNull);
    });
    test('accepts valid name', () {
      expect(Validators.name('Leonardo'), isNull);
    });
  });

  group('Validators.email', () {
    test('rejects empty', () => expect(Validators.email(''), isNotNull));
    test('rejects invalid format', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
    });
    test('accepts valid email', () {
      expect(Validators.email('user@example.com'), isNull);
    });
  });

  group('Validators.password', () {
    test('rejects empty', () => expect(Validators.password(''), isNotNull));
    test('rejects short', () => expect(Validators.password('ab1'), isNotNull));
    test('rejects without letters',
        () => expect(Validators.password('12345678'), isNotNull));
    test('rejects without numbers',
        () => expect(Validators.password('abcdefgh'), isNotNull));
    test('accepts 8+ chars with letters and numbers',
        () => expect(Validators.password('Matrix123'), isNull));
  });

  group('Validators.confirmPassword', () {
    test('rejects empty', () =>
        expect(Validators.confirmPassword('', '123456'), isNotNull));
    test('rejects mismatch', () =>
        expect(Validators.confirmPassword('different', '123456'), isNotNull));
    test('accepts match', () =>
        expect(Validators.confirmPassword('123456', '123456'), isNull));
  });

  group('Validators.required', () {
    test('rejects empty', () => expect(Validators.required(''), isNotNull));
    test('accepts non-empty', () => expect(Validators.required('ok'), isNull));
  });
}
