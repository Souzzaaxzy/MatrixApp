import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/matrix_bottom_bar.dart';
import '../akame/akame_screen.dart';
import '../chat/chat_screen.dart';
import '../feed/feed_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';

/// Main navigation shell with a persistent bottom bar.
///
/// Tabs: Início, Chat, Buscar, Atividades, Perfil. Akame is no longer a
/// separate bottom-bar entry — it lives INSIDE the Chat tab as a fixed,
/// permanent first card in the conversations screen. The post creation
/// flow is reached from the floating "+" button on the own profile —
/// there is no creation entry in the bottom bar anymore.
///
/// Android back at the ROOT of the app follows the system convention:
/// the first press shows "Pressione voltar novamente para sair" and only a
/// second press within 2s closes the app (state resets after the window).
/// Inner routes (post detail, other profiles, create post) pop normally
/// BEFORE this handler ever runs, since they are routes on top.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Time window for the double-press-to-exit confirmation.
  static const Duration _exitWindow = Duration(seconds: 2);

  late int _index = widget.initialIndex.clamp(0, 4);
  bool _primed = false;
  bool _akameOpen = false;

  void _openAkame() {
    setState(() => _akameOpen = true);
  }

  void _closeAkame() {
    if (mounted) setState(() => _akameOpen = false);
  }

  DateTime? _lastBackPress;
  Timer? _exitResetTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_primed) {
      _primed = true;
      // Prime the unread badge early so it shows before the user opens the
      // notifications tab for the first time.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppStateScope.of(context).loadNotifications();
      });
    }
  }

  void _onTap(int i) {
    setState(() => _index = i);
    final state = AppStateScope.of(context);
    if (i == 1) {
      // Opening the Chat tab refreshes conversations + unread badge.
      state.loadConversations();
      state.refreshUnreadConversations();
    } else if (i == 3) {
      // Opening the Atividades tab refreshes the server-side list.
      state.loadNotifications();
    }
  }

  /// One back press while NOT on the feed tab returns to the feed first
  /// (standard bottom-bar behavior); at the root the first press primes
  /// the exit ("press again to exit") and the second within [_exitWindow]
  /// actually closes the app. The pending state auto-resets after 2s.
  void _handleBackPress() {
    if (_index != 0) {
      setState(() => _index = 0);
      _resetExit();
      return;
    }
    if (_lastBackPress != null) {
      _resetExit();
      // Platform-side exit; swallowed in hosts without a handler (tests).
      SystemNavigator.pop().catchError((Object _) {});
      return;
    }
    _lastBackPress = DateTime.now();
    _exitResetTimer = Timer(_exitWindow, _resetExit);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pressione voltar novamente para sair'),
        duration: _exitWindow,
      ),
    );
  }

  void _resetExit() {
    _exitResetTimer?.cancel();
    _exitResetTimer = null;
    _lastBackPress = null;
  }

  @override
  void dispose() {
    _exitResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Touch AppStateScope so the home rebuilds when posts/profile change.
    final state = AppStateScope.of(context);

    final destinations = [
      const MatrixNavDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Início',
      ),
      MatrixNavDestination(
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        label: 'Chat',
        badgeCount: state.unreadConversations,
      ),
      const MatrixNavDestination(
        icon: Icons.search_rounded,
        activeIcon: Icons.search,
        label: 'Buscar',
      ),
      MatrixNavDestination(
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications_rounded,
        label: 'Atividades',
        badgeCount: state.unreadNotifications,
      ),
      const MatrixNavDestination(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Perfil',
      ),
    ];

    // Non-const on purpose: identical const instances are skipped by the
    // element tree on rebuild, which would freeze the previous theme's
    // colors on these tabs (AppColors resolves at build time).
    final pages = <Widget>[
      FeedScreen(),
      ChatScreen(onOpenAkame: _openAkame),
      SearchScreen(),
      NotificationsScreen(),
      ProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // The system back button closes the Akame overlay first when it is
        // open (matching how Android back closes a pushed route).
        if (_akameOpen) {
          _closeAkame();
          return;
        }
        _handleBackPress();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.absoluteBlack,
            body: IndexedStack(index: _index, children: pages),
            bottomNavigationBar: MatrixBottomBar(
              currentIndex: _index,
              destinations: destinations,
              onTap: _onTap,
            ),
          ),
          // Akame lives INSIDE the Chat tab: tapping its card in the
          // conversations screen opens the full standalone chat as an
          // overlay. Its back arrow and the system back button both close it.
          if (_akameOpen)
            Positioned.fill(
              child: AkameOverlay(onClose: _closeAkame),
            ),
        ],
      ),
    );
  }
}

/// Full-screen Akame chat overlay embedded in the Home shell. Because it is
/// NOT a pushed route, the bottom bar and the whole HomeScreen stay mounted
/// underneath; opening/closing is a boolean flip (cheap, no extra queries —
/// Akame messages already live in [AppState]). A fade+scale entrance/rear
/// exit keeps the transition smooth, and the back arrow mirrors the system
/// back behavior.
class AkameOverlay extends StatelessWidget {
  const AkameOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.absoluteBlack,
      child: SafeArea(
        child: Column(
          children: [
            _AkameOverlayBar(onClose: onClose),
            const Expanded(child: AkameScreen()),
          ],
        ),
      ),
    );
  }
}

class _AkameOverlayBar extends StatelessWidget {
  const _AkameOverlayBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bluishBlack,
        border: Border(bottom: BorderSide(color: AppColors.deepBlue, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Fechar Akame',
            icon: Icon(Icons.arrow_back_rounded, color: AppColors.holographicBlue),
            onPressed: onClose,
          ),
          const SizedBox(width: AppDimensions.spaceXs),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('AKAME', style: AppTextStyles.hud),
            ),
          ),
        ],
      ),
    );
  }
}
