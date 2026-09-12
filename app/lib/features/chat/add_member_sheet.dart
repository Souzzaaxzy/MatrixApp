import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/chat_format.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/matrix_user.dart';

/// Result of the add-member picker (a confirmed user to add).
class AddMemberResult {
  const AddMemberResult({required this.userId, required this.nickname});

  final String userId;
  final String nickname;
}

/// Bottom sheet that lists a user's friends (excluding the owner and anyone
/// already in the group) so the group owner can pick one to add..
class AddMemberSheet extends StatefulWidget {
  const AddMemberSheet({
    super.key,
    required this.ownerId,
    required this.existingIds,
  });

  final String ownerId;
  final Set<String> existingIds;

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  List<MatrixUser> _friends = const [];
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
                f.id != widget.ownerId && !widget.existingIds.contains(f.id))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
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
            else
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
                          baseStyle: AppTextStyles.body.copyWith(fontSize: 15),
                          background: AppColors.bluishBlack,
                          nameColor: u.nameColor,
                        ),
                        onTap: () {
                          Navigator.of(context).pop(
                            AddMemberResult(
                                userId: u.id, nickname: u.nickname),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}