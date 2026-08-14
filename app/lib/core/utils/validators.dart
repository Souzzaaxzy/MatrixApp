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

  static final RegExp _username = RegExp(r'^[a-zA-Z0-9_.]+$');

  static String? username(String? value) {
    final v = (value ?? '').trim().replaceAll('@', '');
    if (v.isEmpty) return 'Informe um username';
    if (v.length < 3) return 'Mínimo de 3 caracteres';
    if (!_username.hasMatch(v)) return 'Apenas letras, números, _ e .';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Informe sua senha';
    if (v.length < 6) return 'Mínimo de 6 caracteres';
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
