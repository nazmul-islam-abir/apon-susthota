import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Bold gradient CTA button used by the BDApps login screen.
class AppButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? accent;

  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? AppColors.cyan;
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Ink(
            decoration: BoxDecoration(
              gradient: disabled
                  ? null
                  : LinearGradient(
                      colors: [
                        accentColor,
                        accentColor.withValues(alpha: 0.85),
                      ],
                    ),
              color: disabled ? AppColors.line : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: disabled ? AppColors.smoke : Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    icon,
                    color: disabled ? AppColors.smoke : Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}