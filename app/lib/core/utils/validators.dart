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

  // Mirrors the server rule (ServidorMtx src/utils/normalize.ts): full
  // Unicode — letters (any case/accents), numbers, emojis, symbols and
  // punctuation are all allowed. Blocked: '@' (identity prefix, never part
  // of a nickname), HTML brackets/quotes (injection guard), control/format
  // chars (invisible/zero-width payloads), max 30 chars. The nickname is
  // rendered as plain TEXT everywhere, so escaping is never needed — this
  // check only rejects characters with no legitimate use in a name.
  static final RegExp _nicknameForbidden = RegExp(r'[@<>"' "'" r'`\\]');

  static bool _isForbiddenCodePoint(int rune) {
    // Cc/Cf (control/format: zero-width spaces, bidi overrides, ...) and
    // Cn (unassigned) — everything else, including emojis and
    // mathematical/fraktur letters, is fine.
    if (rune < 0x20 || rune == 0x7F) return true; // Cc
    if (rune >= 0x80 && rune <= 0x9F) return true; // C1 controls
    const formatRanges = [
      [0x200B, 0x200F], // ZWSP..RLM
      [0x202A, 0x202E], // bidi embeddings/overrides
      [0x2060, 0x2064], // word joiner, invisible operators
      [0xFEFF, 0xFEFF], // BOM / zero-width no-break space
    ];
    for (final range in formatRanges) {
      if (rune >= range[0] && rune <= range[1]) return true;
    }
    return false;
  }

  /// The nickname is the single visual identity. Any leading '@' the user
  /// may type is tolerated and normalized away by the server (storage is
  /// canonical, display preserves exactly what the user typed).
  static String? nickname(String? value) {
    final v = (value ?? '').trim().replaceAll('@', '');
    if (v.isEmpty) return 'Informe um nickname';
    if (v.length < 3) return 'Mínimo de 3 caracteres';
    if (v.length > 30) return 'Máximo de 30 caracteres';
    if (_nicknameForbidden.hasMatch(v)) {
      return 'Caracteres não permitidos: @ < > " \' ` \\';
    }
    if (v.runes.any(_isForbiddenCodePoint)) {
      return 'Caracteres invisíveis não são permitidos';
    }
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
