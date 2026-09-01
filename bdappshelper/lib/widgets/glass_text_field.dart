import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Frosted glass text field. Used in login, register, and search inputs.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.hint,
    this.prefix,
    this.suffix,
    this.prefixText,
    this.keyboardType,
    this.obscureText = false,
    this.controller,
    this.onChanged,
    this.maxLines = 1,
    this.textAlign,
    this.textStyle,
  });

  final String hint;
  final Widget? prefix;
  final Widget? suffix;
  final String? prefixText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextAlign? textAlign;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppBlur.sigma, sigmaY: AppBlur.sigma),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.glassWhite, AppColors.glassWhiteSoft],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            onChanged: onChanged,
            maxLines: maxLines,
            textAlign: textAlign ?? TextAlign.start,
            style: textStyle ??
                const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              prefixIcon: prefix,
              prefix: prefixText != null
                  ? Text(
                      prefixText!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    )
                  : null,
              suffixIcon: suffix,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
