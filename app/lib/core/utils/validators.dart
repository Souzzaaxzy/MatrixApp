/// Local input validation helpers for Phase 1.
class Validators {
  Validators._();

  static final RegExp _email = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Returns an error message or null when valid.
  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Informe seu nome';
    if (v.length < 2) return 'Nome muito curto';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Informe seu e-mail';
    if (!_email.hasMatch(v)) return 'E-mail inválido';
    return null;
  }

  static final RegExp _nickname = RegExp(r'^[a-zA-Z0-9_.]+$');

  /// The nickname is the single visual identity. Any leading '@' the user
  /// may type is tolerated and normalized away (storage is canonical).
  static String? nickname(String? value) {
    final v = (value ?? '').trim().replaceAll('@', '');
    if (v.isEmpty) return 'Informe um nickname';
    if (v.length < 3) return 'Mínimo de 3 caracteres';
    if (!_nickname.hasMatch(v)) return 'Apenas letras, números, _ e .';
    return null;
  }

  // Must mirror the server rule (ServidorMtx auth.schema.ts): mínimo de 8
  // caracteres, com letras e números. If they diverge, the form passes
  // locally and the API rejects with 400.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Informe sua senha';
    if (v.length < 8) return 'Mínimo de 8 caracteres';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return 'A senha deve conter letras';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'A senha deve conter números';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    final v = value ?? '';
    if (v.isEmpty) return 'Confirme sua senha';
    if (v != original) return 'As senhas não coincidem';
    return null;
  }

  static String? required(String? value, {String label = 'Campo obrigatório'}) {
    if ((value ?? '').trim().isEmpty) return label;
    return null;
  }
}
