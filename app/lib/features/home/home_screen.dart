import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/matrix_bottom_bar.dart';
import '../akame/akame_screen.dart';
import '../feed/feed_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';

/// Main navigation shell with a persistent bottom bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _index = widget.initialIndex.clamp(0, 4);

  static const _destinations = [
    MatrixNavDestination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Início',
    ),
    MatrixNavDestination(
      icon: Icons.search_rounded,
      activeIcon: Icons.search,
      label: 'Buscar',
    ),
    MatrixNavDestination(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      label: 'Akame',
    ),
    MatrixNavDestination(
      icon: Icons.add_circle_outline_rounded,
      activeIcon: Icons.add_circle_rounded,
      label: 'Criar',
    ),
    MatrixNavDestination(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Perfil',
    ),
  ];

  Future<void> _onTap(int i) async {
    if (i == 3) {
      await Navigator.of(context).pushNamed(AppRoutes.createPost);
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // Touch AppStateScope so the home rebuilds when posts/profile change.
    AppStateScope.of(context);

    final pages = <Widget>[
      const FeedScreen(),
      const SearchScreen(),
      const AkameScreen(),
      const SizedBox.shrink(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: MatrixBottomBar(
        currentIndex: _index,
        destinations: _destinations,
        onTap: _onTap,
      ),
    );
  }
}
