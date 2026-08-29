import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/profile_navigation.dart';
import '../../data/search_history_store.dart';
import '../../models/cosmetic_item.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_card.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/matrix_user.dart';

/// MATRIX search — backend search by nickname.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.historyStore});

  /// Injectable history store (widget tests stand it in with an in-memory
  /// fake). Null → real persistent store (per-user secure storage).
  final SearchHistoryStore? historyStore;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<MatrixUser> _results = const [];
  List<SearchHistoryEntry> _history = const [];
  bool _loading = false;
  bool _searched = false;

  /// The session user whose history is shown (isolated per account).
  String? _historyUserId;
  bool _historyLoaded = false;
  late final SearchHistoryStore _historyStore =
      widget.historyStore ?? SearchHistoryStore();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_historyLoaded) {
      _historyLoaded = true;
      unawaited(_loadHistory());
    }
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
    openUserProfile(context, user);
  }

  Future<void> _loadHistory() async {
    final session = AppStateScope.maybeOf(context)?.currentUser;
    if (session == null) return;
    _historyUserId = session.id;

    try {
      final entries = await _historyStore.load(session.id);
      if (!mounted) return;
      setState(() => _history = entries);
    } catch (_) {
      // Best-effort: search history is cosmetic.



    }
  }

  /// Removes a single history entry(immediate, persisted, others untouched).
  Future<void> _removeHistoryEntry(SearchHistoryEntry entry) async {
    final userId = _historyUserId;
    if (userId == null || entry.id.isEmpty) return;
    setState(() => {
      _history = _history.where((e) => e.id != entry.id).toList();
    });
    unawaited(_historyStore.remove(userId, entry.id));
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
          if (_history.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spaceLg,
                  AppDimensions.spaceLg,
                  AppDimensions.spaceLg,
                  AppDimensions.spaceSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HISTÓRICO',
                      style: AppTextStyles.label,
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    for (final entry in _history)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppDimensions.spaceSm),
                        child: MatrixCard(
                          margin: EdgeInsets.zero,
                          onTap: () {
                            openUserProfileFromHistory(context, entry);
                          },
                          child: Row(
                            children: [
                              FramedAvatar(
                                frame: entry.frameId != null
                                    ? CosmeticItem(
                                        id: entry.frameId!,
                                        slot: CosmeticItem.avatarFrame,
                                        name: entry.frameId!,
                                        assetUrl: entry.frameAsset ?? '',
                                      )
                                    : null,
                                size: 42,
                                child: UserAvatar(
                                  name: entry.nickname,
                                  seed: entry.nickname,
                                  imageUrl: entry.avatarUrl,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(width: AppDimensions.spaceMd),
                              Expanded(
                                child: NicknameRenderer(
                                  entry.nickname,
                                  baseStyle: AppTextStyles.h3,
                                  background: AppColors.cardSurface,
                                  nameColor: entry.nameColor,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remover do histórico',
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: AppColors.holographicBlue,
                                  size: 22,
                                ),
                                onPressed: () => _removeHistoryEntry(entry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppDimensions.spaceMd),
                  ],
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
                        FramedAvatar(
                          frame: user.frame,
                          size: 42,
                          child: UserAvatar(
                            name: user.nickname,
                            seed: user.avatarSeed ?? user.nickname,
                            imageUrl: user.avatarUrl,
                            size: 36,
                          ),
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
