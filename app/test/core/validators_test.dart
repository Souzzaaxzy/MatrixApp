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

  group('Validators.nickname (Unicode)', () {
    test('rejects empty / too short / too long', () {
      expect(Validators.nickname(''), isNotNull);
      expect(Validators.nickname('ab'), isNotNull);
      expect(Validators.nickname('a' * 31), isNotNull);
    });

    test('accepts plain, uppercase, mixed case', () {
      expect(Validators.nickname('Leonardo'), isNull);
      expect(Validators.nickname('LEONARDO'), isNull);
      expect(Validators.nickname('LeOnArDo'), isNull);
    });

    test('accepts emojis, symbols, accents and Unicode letters', () {
      expect(Validators.nickname('Leonardo 🔥'), isNull);
      expect(Validators.nickname('★Leonardo★'), isNull);
      expect(Validators.nickname('𝕷𝖊𝖔𝖓𝖆𝖗𝖉𝖔'), isNull);
      expect(Validators.nickname('LΞONΛRDO'), isNull);
      expect(Validators.nickname('Leonardo.exe'), isNull);
      expect(Validators.nickname('MATRIX ⚡'), isNull);
      expect(Validators.nickname('José Álvares'), isNull);
    });

    test('never transforms the input (no lowercase / no stripping)', () {
      // The validator only VALIDATES; it must never return a transformed
      // value. Case, emojis and symbols are preserved end-to-end.
      expect(Validators.nickname('LeOnArDo 🔥'), isNull);
    });

    test('still blocks injection payloads and invisible characters', () {
      expect(Validators.nickname('<script>alert(1)</script>'), isNotNull);
      expect(Validators.nickname('"><img src=x>'), isNotNull);
      expect(Validators.nickname('nick`name'), isNotNull);
      expect(Validators.nickname('nick\\name'), isNotNull);
      expect(Validators.nickname('Leo​nardo'), isNotNull); // ZWSP
      expect(Validators.nickname('Leo\u202Enardo'), isNotNull); // bidi override
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
