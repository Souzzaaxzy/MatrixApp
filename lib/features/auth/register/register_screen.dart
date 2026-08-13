import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/animations/fade_slide_transition.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/hud_label.dart';
import '../../../core/widgets/matrix_button.dart';
import '../../../core/widgets/matrix_text_field.dart';

/// Register screen. Validation is local in Phase 1 (no real auth).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _confirmObscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    // Simulated registration — replace with real auth later.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceXl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideTransition(
                  child: Center(
                    child: Column(
                      children: [
                        Text('CRIAR CONTA', style: AppTextStyles.h1),
                        const SizedBox(height: AppDimensions.spaceSm),
                        const HudLabel(text: 'JOIN THE NETWORK', dot: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 120),
                  child: MatrixTextField(
                    label: 'Nome',
                    hint: 'Seu nome',
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: Validators.name,
                    prefix: const Icon(Icons.person_outline_rounded,
                        color: AppColors.holographicBlue, size: 20),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 200),
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
                  delay: const Duration(milliseconds: 280),
                  child: MatrixTextField(
                    label: 'Senha',
                    hint: 'Mínimo de 6 caracteres',
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    validator: Validators.password,
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
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 360),
                  child: MatrixTextField(
                    label: 'Confirmar senha',
                    hint: 'Repita a senha',
                    controller: _confirmController,
                    obscureText: _confirmObscure,
                    textInputAction: TextInputAction.done,
                    validator: (v) =>
                        Validators.confirmPassword(v, _passwordController.text),
                    onFieldSubmitted: (_) => _submit(),
                    prefix: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.holographicBlue, size: 20),
                    suffix: IconButton(
                      icon: Icon(
                        _confirmObscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.holographicBlue,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _confirmObscure = !_confirmObscure),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 440),
                  child: MatrixButton(
                    label: 'Criar conta',
                    expanded: true,
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 500),
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
                  delay: const Duration(milliseconds: 560),
                  child: MatrixButton(
                    label: 'Continuar com Google',
                    icon: Icons.g_mobiledata_rounded,
                    variant: MatrixButtonVariant.outline,
                    expanded: true,
                    onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 640),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Já possui uma conta?', style: AppTextStyles.bodyMuted),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Entrar',
                            style: AppTextStyles.label
                                .copyWith(color: AppColors.electricBlue)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
