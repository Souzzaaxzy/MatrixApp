import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/chat_format.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/matrix_user.dart';

/// Result of the add-member picker (the confirmed selection + each picked
/// user's nickname for the success snackbar).
class AddMemberResult {
  const AddMemberResult({required this.userId, required this.nickname});

  final String userId;
  final String nickname;
}

/// Bottom sheet that lists a user's friends (excluding the owner, anyone
/// already in the group AND anyone currently banned — banned users are NOT
/// active members) so the group owner can pick one to add..
class AddMemberSheet extends StatefulWidget {
  const AddMemberSheet({
    super.key,
    required this.ownerId,
    required this.existingIds,
    this.bannedIds = const {},
  });

  final String ownerId;

  /// Active member ids of the group (banned users are excluded from this set).
  final Set<String> existingIds;

  /// Currently-banned member ids of the group — they must never be offered
  /// as "addable": they are NOT active members and require an unban first.
  final Set<String> bannedIds;

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  List<MatrixUser> _friends = const [];

  /// Ids of the friends currently ticked (select/deselect before confirming).
  final Set<String> _selected = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    final current = state.currentUser;
    if (current == null) return;
    try {
      final page = await state.loadFriends(current.id, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _friends = page.friends
            .where((f) =>
                f.id != widget.ownerId &&
                !widget.existingIds.contains(f.id) &&
                !widget.bannedIds.contains(f.id))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Toggles a friend in/out of the pending selection (Etapa 3: selecionar /
  /// desselecionar antes de confirmar).
  void _toggle(MatrixUser u) {
    setState(() {
      if (!_selected.add(u.id)) {
        _selected.remove(u.id);
      }
    });
  }

  void _confirm() {
    if (_selected.isEmpty) return;
    // Add the FIRST selected user; the caller adds them and refreshes,
    // so the next open of the sheet excludes the newly-added member.
    final chosen = _friends.firstWhere((f) => _selected.contains(f.id));
    Navigator.of(context).pop(
      AddMemberResult(userId: chosen.id, nickname: chosen.nickname),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bluishBlack,
          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        ),
        // Transparent Material so the ListTiles below find a Material
        // ancestor (the Container's decoration would otherwise hide their
        // ink splashes — newer Flutter asserts on that).
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spaceLg),
                child: Text('ADICIONAR MEMBRO',
                    style: AppTextStyles.hud
                        .copyWith(fontSize: 14, color: AppColors.techWhite)),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              if (_loading)
                Padding(
                  padding: EdgeInsets.all(24),
                  child:
                      Center(child: HudLabel(text: 'CARREGANDO...', dot: true)),
                )
              else if (_friends.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('Nenhum amigo disponível para adicionar.',
                        style: AppTextStyles.bodyMuted,
                        textAlign: TextAlign.center),
                  ),
                )
              else ...[
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in _friends)
                        ListTile(
                          leading: FramedAvatar(
                            frame: u.frame,
                            size: 44,
                            child: UserAvatar(
                              name: u.nickname,
                              seed: u.nickname,
                              imageUrl: u.avatarUrl,
                              size: 36,
                            ),
                          ),
                          title: NicknameRenderer(
                            displayNickname(u.nickname),
                            baseStyle:
                                AppTextStyles.body.copyWith(fontSize: 15),
                            background: AppColors.bluishBlack,
                            nameColor: u.nameColor,
                          ),
                          trailing: Checkbox(
                            value: _selected.contains(u.id),
                            onChanged: (_) => _toggle(u),
                            activeColor: AppColors.holographicBlue,
                            checkColor: AppColors.absoluteBlack,
                          ),
                          onTap: () => _toggle(u),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spaceLg),
                  child: Row(
                    children: [
                      Expanded(
                        child: MatrixButton(
                          label: 'CANCELAR',
                          expanded: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spaceMd),
                      Expanded(
                        child: MatrixButton(
                          label: _selected.isEmpty
                              ? 'ADICIONAR'
                              : 'ADICIONAR (${_selected.length})',
                          expanded: true,
                          onPressed: _selected.isEmpty ? null : _confirm,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
