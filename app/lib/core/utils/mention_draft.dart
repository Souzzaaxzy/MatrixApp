import '../../models/conversation.dart';

/// A mention selected in the suggestion menu and anchored to a text range in
/// the composer. The range is the ONLY link between the visual "@Nickname"
/// token and the real user — any edit that mutates the token destroys the
/// mention permanently (even if the user later restores the original text).
class MentionDraft {
  const MentionDraft({
    required this.userId,
    required this.nickname,
    required this.start,
    required this.end,
    this.all = false,
  });

  /// Empty id when [all] is true (@todos).
  final String userId;
  final String nickname;
  final int start;
  final int end;
  final bool all;

  int get length => end - start;

  String token(String text) =>
      (start < 0 || end > text.length || end <= start)
          ? ''
          : text.substring(start, end);

  /// True when the token at [start..end) is still UNCHANGED, at a word
  /// boundary and exactly "@Nickname"/"@todos".
  bool intact(String text) =>
      _matches(text, start, end, expectedToken());

  String expectedToken() => all ? '@todos' : '@$nickname';

  ChatMention toMention() => ChatMention(
        userId: userId,
        nickname: nickname,
        all: all,
        start: start,
        end: end,
      );

  MentionDraft shiftedBy(int delta) => MentionDraft(
        userId: userId,
        nickname: nickname,
        start: start + delta,
        end: end + delta,
        all: all,
      );

  static bool _matches(String text, int s, int e, String expected) {
    if (s < 0 || e > text.length || e <= s) return false;
    if (s > 0 && !_isSpace(text.codeUnitAt(s - 1))) return false;
    if (e < text.length && _isWordChar(text.codeUnitAt(e))) return false;
    return text.substring(s, e) == expected;
  }

  static bool _isSpace(int unit) => RegExp(r'\s').hasMatch(String.fromCharCode(unit));
  static bool _isWordChar(int unit) =>
      RegExp(r'[\w\u00C0-\uFFFF]').hasMatch(String.fromCharCode(unit));
}

/// Maintains the draft mentions of a composer across arbitrary text edits.
///
/// How it survives edits:
/// - Any draft whose range overlaps the edited region is dropped FOREVER
///   (there is no "edit and revert restores the mention" — a mention only
///   exists while its exact token text was never touched).
/// - Drafts fully BEFORE the change keep their offsets.
/// - Drafts fully AFTER the change are shifted by the length delta.
/// - Inserting text directly before a mention (after a trailing space) shifts
///   it; writing INTO the mention or gluing new word-chars to its edges
///   destroys it.
class MentionDraftTracker {
  MentionDraftTracker({List<MentionDraft> initial = const []})
      : _drafts = List.of(initial);

  List<MentionDraft> _drafts;

  List<MentionDraft> get drafts => List.unmodifiable(_drafts);

  /// Reconciles the draft list with a full replacement of the composer text
  /// (driven by onChanged, where Flutter reports the whole value). [before]
  /// is the previous composer value, [after] the new one.
  void applyEdit(String before, String after) {
    final commonPrefix = _commonPrefix(before, after);
    final commonSuffix = _commonSuffix(before, after);
    final oldRegionStart = commonPrefix;
    final oldRegionEnd = before.length - commonSuffix;
    final newRegionLength = after.length - commonPrefix - commonSuffix;
    final delta = newRegionLength - (oldRegionEnd - oldRegionStart);

    // Compute the pre-edit token ranges so we can detect which drafts were
    // touched. A draft whose range does NOT overlap the edited region and is
    // NOT glued to its edges survives (shifted if it comes after the change).
    final next = <MentionDraft>[];
    for (final d in _drafts) {
      final s = d.start;
      final e = d.end;
      if (e <= oldRegionStart) {
        // fully before the edit — untouched.
        next.add(d);
      } else if (s >= oldRegionEnd) {
        // fully after the edit — shift by the length delta.
        final shifted = d.shiftedBy(delta);
        if (shifted.start >= 0 && shifted.end <= after.length) {
          next.add(shifted);
        }
      } else {
        // Overlaps the edited region — destroyed FOREVER (an edit-and-revert
        // does NOT restore the mention).
      }
    }
    _drafts = next;
    _validateAndKeep(after);
  }

  /// Records a selection made through the suggestion menu. [tokenStart] /
  /// [tokenEnd] point at the "@Nickname"/"@todos" token to anchor.
  void insert(MentionDraft draft) {
    // Remove any existing draft occupying the same token range (a re-pick
    // replaces the placeholder), keep the rest.
    _drafts = [
      for (final d in _drafts)
        if (d.start != draft.start || d.end != draft.end) d,
      draft,
    ];
  }

  /// Replaces the whole draft list (used when the composer text is rewritten
  /// programmatically by a mention insertion).
  void replaceAll(List<MentionDraft> drafts) {
    _drafts = List.of(drafts);
  }

  /// All currently-valid drafts as sendable [ChatMention]s (trimmed content
  /// offsets are not remapped here — the caller sends them in content space;
  /// the server validates ranges against the received content).
  List<ChatMention> validMentions() =>
      [for (final d in _drafts) d.toMention()];

  void clear() {
    _drafts = [];
  }

  void _validateAndKeep(String text) {
    _drafts = [for (final d in _drafts) if (d.intact(text)) d];
  }

  // Compute the longest common prefix/suffix lengths of two strings
  // (UTF-16 code-unit based, matching Flutter's text offsets).
  int _commonPrefix(String a, String b) {
    final max = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < max && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  int _commonSuffix(String a, String b) {
    final max = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < max &&
        a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
      i++;
    }
    return i;
  }
}