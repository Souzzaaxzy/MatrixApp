import 'package:flutter/material.dart';

import '../utils/mention_draft.dart';

/// A `TextEditingController` for mention composers.
///
/// The underlying text stays PLAIN ("@Nickname" / "@todos" with their real
/// offsets) — the mention system (parsing, ranges, server payload) is
/// untouched. This controller only adds a VISUAL layer: every still-valid
/// draft mention token is rendered in bold inside the input field, while all
/// surrounding text keeps the normal style. Deleting or editing a token makes
/// the tracker drop the draft, so the bold disappears automatically.
class MentionComposerController extends TextEditingController {
  MentionComposerController({this.getMentions});

  /// Supplies the CURRENT draft mentions (composer space) to bold. Hooked to
  /// the composer's [MentionDraftTracker] — mutated before every rebuild.
  final List<MentionDraft> Function()? getMentions;

  /// Rebuilds the visible text spans after the draft mention set changed
  /// without an accompanying value change (e.g. insert/restore/invalidate).
  void refresh() => notifyListeners();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final drafts = getMentions?.call() ?? const <MentionDraft>[];
    if (drafts.isEmpty) return TextSpan(style: base, text: text);

    final spans = <TextSpan>[];
    var last = 0;
    for (final range in _validRanges(drafts)) {
      if (range.start < last || range.end > text.length || range.end <= range.start) {
        continue;
      }
      if (range.start > last) {
        spans.add(TextSpan(text: text.substring(last, range.start)));
      }
      // ONLY the mention token is bolded — never the surrounding message.
      spans.add(TextSpan(
        text: text.substring(range.start, range.end),
        style: base.copyWith(fontWeight: FontWeight.w800),
      ));
      last = range.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return TextSpan(style: base, children: spans);
  }

  /// Drafts whose token text is byte-identical to "@Nickname"/"@todos", in
  /// ascending start order (the same rule the message renderer uses).
  List<({int start, int end})> _validRanges(List<MentionDraft> drafts) {
    final out = <({int start, int end})>[];
    for (final d in drafts) {
      if (d.start < 0 || d.end > text.length || d.end <= d.start) continue;
      if (text.substring(d.start, d.end) != d.expectedToken()) continue;
      out.add((start: d.start, end: d.end));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}