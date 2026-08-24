import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/animations/fade_slide_transition.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_state_scope.dart';
import '../../../core/widgets/glow_container.dart';
import '../../../core/widgets/hud_label.dart';
import '../../../core/widgets/matrix_button.dart';
import '../../../core/widgets/matrix_text_field.dart';
import '../../../data/api_config.dart';

/// Login screen. The flow is simulated in Phase 1 (no real auth).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppStateScope.of(context).login(
        username: _usernameController.text.trim().replaceAll('@', ''),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao entrar.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
                    child: Text(
                      _error!,
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 250),
                  child: MatrixTextField(
                    label: 'Username',
                    hint: 'seu_usuario',
                    controller: _usernameController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    validator: Validators.username,
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
                    // Login aceita qualquer senha não vazia — quem valida a
                    // regra de força é o cadastro (e o servidor decide se a
                    // credencial confere). Bloquear aqui impediria o envio.
                    validator: (v) =>
                        Validators.required(v, label: 'Informe sua senha'),
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
                const SizedBox(height: AppDimensions.spaceSm),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 360),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.recover),
                      child: Text('Esqueci a senha',
                          style: AppTextStyles.label
                              .copyWith(color: AppColors.holographicBlue)),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 400),
                  child: MatrixButton(
                    label: 'Entrar',
                    expanded: true,
                    isLoading: _loading,
                    onPressed: _submit,
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
