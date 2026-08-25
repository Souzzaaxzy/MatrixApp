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

/// Account recovery screen. The user supplies their username/MATRIX ID,
/// the recovery code shown at registration, and a new password. No email
/// or phone is involved — recovery is code-based only.
class RecoverScreen extends StatefulWidget {
  const RecoverScreen({super.key});

  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _confirmObscure = true;
  bool _loading = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _codeController.dispose();
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
      await AppStateScope.of(context).recover(
        identifier: _identifierController.text.trim().replaceAll(RegExp(r'^@+'), ''),
        recoveryCode: _codeController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _done = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Dados de recuperação inválidos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          child: _done ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FadeSlideTransition(
            child: Center(
              child: Column(
                children: [
                  Text('RECUPERAR CONTA', style: AppTextStyles.h1),
                  const SizedBox(height: AppDimensions.spaceSm),
                  const HudLabel(text: 'RECOVERY PROTOCOL', dot: true),
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
              label: 'Username ou MATRIX ID',
              hint: 'seu_usuario',
              controller: _identifierController,
              textInputAction: TextInputAction.next,
              validator: (v) => Validators.required(v, label: 'Informe seu username'),
              prefix: Icon(Icons.person_outline_rounded,
                  color: AppColors.holographicBlue, size: 20),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          FadeSlideTransition(
            delay: const Duration(milliseconds: 180),
            child: MatrixTextField(
              label: 'Código de recuperação',
              hint: '12 caracteres',
              controller: _codeController,
              textInputAction: TextInputAction.next,
              validator: (v) => Validators.required(v, label: 'Informe o código'),
              prefix: Icon(Icons.password_rounded,
                  color: AppColors.holographicBlue, size: 20),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          FadeSlideTransition(
            delay: const Duration(milliseconds: 240),
            child: MatrixTextField(
              label: 'Nova senha',
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
            delay: const Duration(milliseconds: 300),
            child: MatrixTextField(
              label: 'Confirmar nova senha',
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
            delay: const Duration(milliseconds: 360),
            child: MatrixButton(
              label: 'Recuperar conta',
              expanded: true,
              isLoading: _loading,
              onPressed: _submit,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXxl),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppDimensions.spaceXxl),
        const Icon(Icons.lock_open_rounded, color: AppColors.success, size: 64),
        const SizedBox(height: AppDimensions.spaceLg),
        Text('SENHA REDEFINIDA',
            textAlign: TextAlign.center, style: AppTextStyles.h2),
        const SizedBox(height: AppDimensions.spaceMd),
        Text(
          'Sua senha foi redefinida com sucesso. Faça login com a nova senha.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: AppDimensions.spaceXxl),
        MatrixButton(
          label: 'Ir para o login',
          expanded: true,
          onPressed: () => Navigator.of(context)
            ..popUntil((r) => r.settings.name == AppRoutes.login),
        ),
      ],
    );
  }
}
