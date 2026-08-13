import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/animations/fade_slide_transition.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/glow_container.dart';
import '../../../core/widgets/hud_label.dart';
import '../../../core/widgets/matrix_button.dart';
import '../../../core/widgets/matrix_text_field.dart';

/// Login screen. The flow is simulated in Phase 1 (no real auth).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    // Simulated access flow — replace with real authentication later.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceXl,
            vertical: AppDimensions.spaceXxl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  child: Center(
                    child: GlowContainer(
                      glow: Glow.medium,
                      color: AppColors.glowMedium,
                      background: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spaceXl,
                        vertical: AppDimensions.spaceLg,
                      ),
                      child: Text('MATRIX', style: AppTextStyles.display),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 150),
                  child: const Center(child: HudLabel(text: 'ACCESS NETWORK', dot: true)),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 250),
                  child: MatrixTextField(
                    label: 'E-mail',
                    hint: 'seu@email.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: Validators.email,
                    prefix: const Icon(Icons.alternate_email_rounded,
                        color: AppColors.holographicBlue, size: 20),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 320),
                  child: MatrixTextField(
                    label: 'Senha',
                    hint: '••••••••',
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    validator: Validators.password,
                    onFieldSubmitted: (_) => _submit(),
                    prefix: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.holographicBlue, size: 20),
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.holographicBlue,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 400),
                  child: MatrixButton(
                    label: 'Entrar',
                    expanded: true,
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 460),
                  child: Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.deepBlue)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd),
                        child: Text('ou', style: AppTextStyles.caption),
                      ),
                      const Expanded(child: Divider(color: AppColors.deepBlue)),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 520),
                  child: MatrixButton(
                    label: 'Google',
                    icon: Icons.g_mobiledata_rounded,
                    variant: MatrixButtonVariant.outline,
                    expanded: true,
                    onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 600),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Ainda não possui uma conta?',
                          style: AppTextStyles.bodyMuted),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.register),
                        child: Text('Criar conta',
                            style: AppTextStyles.label
                                .copyWith(color: AppColors.electricBlue)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
