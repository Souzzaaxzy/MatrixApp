import 'package:flutter/material.dart';

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
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _index = widget.initialIndex.clamp(0, 4);
  bool _primed = false;

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

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: MatrixBottomBar(
        currentIndex: _index,
        destinations: destinations,
        onTap: _onTap,
      ),
    );
  }
}
