import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';

/// MATRIX styled text field with focus glow.
class MatrixTextField extends StatefulWidget {
  const MatrixTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.focusNode,
    this.validator,
    this.onFieldSubmitted,
    this.onChanged,
    this.suffix,
    this.prefix,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.enabled = true,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final Widget? prefix;
  final int? maxLines;
  final int? minLines;
  final bool autofocus;
  final bool enabled;

  @override
  State<MatrixTextField> createState() => _MatrixTextFieldState();
}

class _MatrixTextFieldState extends State<MatrixTextField> {
  late FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _handleFocus() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus != _focused) {
      setState(() => _focused = hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        _focused ? AppColors.primaryBlue : AppColors.deepBlue;
    final glow = _focused
        ? [
            BoxShadow(
              color: AppColors.glowSmall,
              blurRadius: AppDimensions.glowSmallBlur,
            ),
          ]
        : const <BoxShadow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!.toUpperCase(), style: AppTextStyles.label),
          const SizedBox(height: AppDimensions.spaceSm),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppColors.bluishBlack,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            boxShadow: glow,
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            textInputAction: widget.textInputAction,
            validator: widget.validator,
            onFieldSubmitted: widget.onFieldSubmitted,
            onChanged: widget.onChanged,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            style: AppTextStyles.body,
            cursorColor: AppColors.electricBlue,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTextStyles.bodyMuted,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg,
                vertical: AppDimensions.spaceLg,
              ),
              suffixIcon: widget.suffix,
              prefixIcon: widget.prefix,
              border: InputBorder.none,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: BorderSide(
                  color: borderColor,
                  width: AppDimensions.borderWidthThin,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: BorderSide(
                  color: AppColors.primaryBlue,
                  width: AppDimensions.borderWidthActive,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: const BorderSide(color: AppColors.error, width: 1.5),
              ),
              errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
