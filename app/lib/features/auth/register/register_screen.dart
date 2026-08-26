import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/animations/fade_slide_transition.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_state_scope.dart';
import '../../../core/widgets/hud_label.dart';
import '../../../core/widgets/matrix_button.dart';
import '../../../core/widgets/matrix_text_field.dart';
import '../../../data/api_config.dart';

/// Register screen. Validation is local in Phase 1 (no real auth).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _confirmObscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recoveryCode = await AppStateScope.of(context).register(
        nickname: _nicknameController.text.trim().replaceAll(RegExp(r'^@+'), ''),
        password: _passwordController.text,
      );
      if (!mounted) return;
      // Show the one-time recovery code before entering the app.
      await _showRecoveryCode(recoveryCode);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao criar conta.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRecoveryCode(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('CÓDIGO DE RECUPERAÇÃO',
            style: AppTextStyles.h3.copyWith(color: AppColors.success)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Guarde este código em local seguro. Ele é a única forma de '
              'recuperar sua conta se esquecer a senha. Não o perdemos e não '
              'podemos reenviá-lo.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: AppTextStyles.h2.copyWith(
                color: AppColors.electricBlue,
                fontFamily: 'JetBrainsMono',
                letterSpacing: 4,
              ),
            ),
          ],
        ),
        actions: [
          MatrixButton(
            label: 'Entendi',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
                    child: Text(
                      _error!,
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 120),
                  child: MatrixTextField(
                    label: 'Nickname',
                    hint: 'Leonardo',
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    validator: Validators.nickname,
                    prefix: Icon(Icons.person_outline_rounded,
                        color: AppColors.holographicBlue, size: 20),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                FadeSlideTransition(
                  delay: const Duration(milliseconds: 280),
                  child: MatrixTextField(
                    label: 'Senha',
                    hint: 'Mínimo de 8, com letras e números',
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    validator: Validators.password,
                    prefix: Icon(Icons.lock_outline_rounded,
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
                    prefix: Icon(Icons.lock_outline_rounded,
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
