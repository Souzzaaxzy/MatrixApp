import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/matrix_bottom_bar.dart';
import '../akame/akame_screen.dart';
import '../feed/feed_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';

/// Main navigation shell with a persistent bottom bar.
///
/// Tabs: Início, Buscar, Akame, Atividades, Perfil. The post creation
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
    if (i == 3) {
      // Opening the tab refreshes the server-side list.
      AppStateScope.of(context).loadNotifications();
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
      const MatrixNavDestination(
        icon: Icons.search_rounded,
        activeIcon: Icons.search,
        label: 'Buscar',
      ),
      const MatrixNavDestination(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: 'Akame',
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

    final pages = <Widget>[
      const FeedScreen(),
      const SearchScreen(),
      const AkameScreen(),
      const NotificationsScreen(),
      const ProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: AppColors.absoluteBlack,
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: MatrixBottomBar(
          currentIndex: _index,
          destinations: destinations,
          onTap: _onTap,
        ),
      ),
    );
  }
}
