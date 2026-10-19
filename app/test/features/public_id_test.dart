import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/validators.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/matrix_user.dart';

import '../helpers/test_app.dart';

/// The public `#id` (`#00000001`): shown small under the nickname on the
/// profile, accepted as a login identifier, and usable to find people.
void main() {
  group('MatrixUser — #id', () {
    test('formats the label from the numeric id when the server omits it', () {
      const u = MatrixUser(id: 'u', nickname: 'neo', publicId: 7);
      expect(u.publicIdText, '#00000007');
    });

    test('prefers the server-provided label', () {
      const u = MatrixUser(
        id: 'u',
        nickname: 'neo',
        publicId: 7,
        publicIdLabel: '#00000007',
      );
      expect(u.publicIdText, '#00000007');
    });

    test('is null when the payload carried no id', () {
      const u = MatrixUser(id: 'u', nickname: 'neo');
      expect(u.publicIdText, isNull);
    });

    test('copyWith keeps the id and can replace it', () {
      const u = MatrixUser(id: 'u', nickname: 'neo', publicId: 7);
      expect(u.copyWith(bio: 'x').publicId, 7);
      expect(u.copyWith(publicId: () => 9).publicId, 9);
    });
  });

  group('Validators.loginIdentifier', () {
    test('accepts a nickname', () {
      expect(Validators.loginIdentifier('leonardo'), isNull);
    });

    test('accepts the #id with and without the leading #', () {
      expect(Validators.loginIdentifier('#00000001'), isNull);
      expect(Validators.loginIdentifier('1'), isNull);
      expect(Validators.loginIdentifier('#42'), isNull);
    });

    test('accepts a nickname with a leading @ (tolerated)', () {
      expect(Validators.loginIdentifier('@leonardo'), isNull);
    });

    test('rejects an empty field', () {
      expect(Validators.loginIdentifier(''), isNotNull);
      expect(Validators.loginIdentifier('   '), isNotNull);
    });

    test('rejects an invalid nickname (too short, not an id)', () {
      expect(Validators.loginIdentifier('ab'), isNotNull);
    });
  });

  group('Perfil — #id abaixo do nickname', () {
    testWidgets('mostra o #id pequeno abaixo do nickname', (tester) async {
      await pumpMatrixApp(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('#00000001'), findsOneWidget);
      expect(find.textContaining('leonardo', findRichText: true), findsOneWidget);

      // O #id fica ABAIXO do nickname e é MUITO menor (pedido do usuário).
      final nickname = tester.getRect(
        find.textContaining('leonardo', findRichText: true),
      );
      final id = tester.getRect(find.text('#00000001'));
      expect(id.top, greaterThanOrEqualTo(nickname.bottom - 1));

      final idStyle = tester.widget<Text>(find.text('#00000001')).style;
      expect(idStyle?.fontSize, isNotNull);
      expect(idStyle!.fontSize!, lessThan(22)); // << nickname (22)
    });

    testWidgets('mostra o #id do usuário VISITADO, não o da sessão',
        (tester) async {
      // 'joao' (u2) tem #00000002; a sessão é 'leonardo' (#00000001).
      await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('#00000002'), findsOneWidget);
      expect(find.text('#00000001'), findsNothing);
    });

    testWidgets('não quebra o layout quando o payload não traz #id',
        (tester) async {
      // Um usuário sem publicId (payload leve) apenas omite a linha.
      const user = MatrixUser(id: 'x', nickname: 'semid');
      expect(user.publicIdText, isNull);
      // A tela de perfil continua renderizando o avatar.
      await pumpMatrixApp(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(UserAvatar), findsWidgets);
    });
  });

  group('Login — campo aceita nickname ou #id', () {
    testWidgets('rotula e aceita o #id', (tester) async {
      await pumpMatrixApp(tester, const LoginScreen());

      expect(find.text('NICKNAME OU #ID'), findsOneWidget);

      // Digitar um #id passa pela validação local (não é bloqueado).
      await tester.enterText(find.byType(TextField).at(0), '#00000001');
      await tester.enterText(find.byType(TextField).at(1), 'SenhaForte123');
      await tester.tap(find.text('ENTRAR'));
      await tester.pump();

      // Sem erro de validação do campo de identificação.
      expect(find.text('Mínimo de 3 caracteres'), findsNothing);
    });
  });
}
