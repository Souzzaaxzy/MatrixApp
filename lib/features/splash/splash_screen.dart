import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/routes.dart';
import '../../core/animations/fade_slide_transition.dart';
import '../../core/widgets/glow_container.dart';

/// Elegant MATRIX splash screen.
///
/// Plays a short, smooth animation then navigates to login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeSlideTransition(
                child: GlowContainer(
                  glow: Glow.medium,
                  color: AppColors.glowMedium,
                  background: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spaceXxl,
                    vertical: AppDimensions.spaceLg,
                  ),
                  child: Text(
                    'MATRIX',
                    style: AppTextStyles.display.copyWith(fontSize: 44),
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              FadeSlideTransition(
                delay: const Duration(milliseconds: 200),
                child: Text('MATRIX NETWORK', style: AppTextStyles.hud),
              ),
              const SizedBox(height: AppDimensions.spaceXxl),
              FadeSlideTransition(
                delay: const Duration(milliseconds: 350),
                child: SizedBox(
                  width: 220,
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) {
                      final value = _progressController.value;
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 4,
                              backgroundColor: AppColors.nightBlue,
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.electricBlue,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spaceSm),
                          Text(
                            'SYSTEM INITIALIZING... ${(value * 100).toInt()}%',
                            style: AppTextStyles.hud.copyWith(fontSize: 10),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
