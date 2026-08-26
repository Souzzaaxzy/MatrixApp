import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_card.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/matrix_user.dart';

/// MATRIX search — backend search by nickname.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<MatrixUser> _results = const [];
  bool _loading = false;
  bool _searched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_searched) {
      _search('');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final users = await AppStateScope.of(context).searchUsers(query.trim());
      if (!mounted) return;
      setState(() {
        _results = users;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searched = true;
        _loading = false;
      });
    }
  }

  void _openUser(MatrixUser user) {
    Navigator.of(context).pushNamed(AppRoutes.profile, arguments: user.nickname);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.absoluteBlack,
            surfaceTintColor: Colors.transparent,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MATRIX SEARCH', style: AppTextStyles.title.copyWith(fontSize: 18)),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spaceLg,
                AppDimensions.spaceSm,
                AppDimensions.spaceLg,
                AppDimensions.spaceLg,
              ),
              child: MatrixTextField(
                hint: 'Pesquisar usuários...',
                controller: _controller,
                prefix: Icon(Icons.search_rounded,
                    color: AppColors.holographicBlue, size: 20),
                onChanged: (v) => _search(v),
              ),
            ),
          ),
          if (_loading && results.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: HudLabel(text: 'SEARCHING...', dot: true)),
            )
          else if (results.isEmpty && _searched)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.person_search_rounded,
                title: 'NO RESULTS',
                hud: 'QUERY EMPTY',
                subtitle: 'Nenhum usuário encontrado.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg,
              ),
              sliver: SliverList.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final user = results[i];
                  return MatrixCard(
                    margin: const EdgeInsets.symmetric(vertical: AppDimensions.spaceSm),
                    onTap: () => _openUser(user),
                    child: Row(
                      children: [
                        UserAvatar(
                          name: user.nickname,
                          seed: user.avatarSeed ?? user.nickname,
                          imageUrl: user.avatarUrl,
                          size: 42,
                        ),
                        const SizedBox(width: AppDimensions.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              NicknameRenderer(
                                user.nickname,
                                baseStyle: AppTextStyles.h3,
                                background: AppColors.cardSurface,
                                nameColor: user.nameColor,
                                effect: user.nameEffect,
                                lightweight: true,
                              ),
                            ],
                          ),
                        ),
                        const HudLabel(text: 'USER', dot: false),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppDimensions.spaceXxl),
          ),
        ],
      ),
    );
  }
}
