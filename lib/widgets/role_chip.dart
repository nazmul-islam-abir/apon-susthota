/// Small chip shown in the app shell header to indicate the active role
/// (patient vs. caregiver). Used by both shells so the user always knows
/// which lens they are looking at the data through.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Which persona the signed-in user is acting as right now.
enum UserRoleView { patient, caregiver }

/// Visual descriptor for a role pill — accent color, icon, label, and
/// a short tooltip-style caption.
class RoleChip extends StatelessWidget {
  final UserRoleView role;
  final bool dense;

  const RoleChip({
    super.key,
    required this.role,
    this.dense = false,
  });

  Color get _accent =>
      role == UserRoleView.caregiver ? AppColors.violet : AppColors.cyan;
  Color get _accentDeep =>
      role == UserRoleView.caregiver ? AppColors.violetDeep : AppColors.cyanDeep;
  IconData get _icon =>
      role == UserRoleView.caregiver
          ? Icons.volunteer_activism_rounded
          : Icons.person_rounded;
  String get _label =>
      role == UserRoleView.caregiver ? 'কেয়ারগিভার' : 'রোগী';
  String get _caption =>
      role == UserRoleView.caregiver ? 'অবলোকন মোড' : 'ব্যক্তিগত মোড';

  @override
  Widget build(BuildContext context) {
    final h = dense ? 28.0 : 32.0;
    final pad = dense ? 10.0 : 12.0;
    final iconSize = dense ? 14.0 : 16.0;
    final fontSize = dense ? 11.5 : 12.5;
    final captionSize = dense ? 9.5 : 10.5;

    return Semantics(
      label: 'বর্তমান ভূমিকা: $_label',
      child: Container(
        height: h,
        padding: EdgeInsets.symmetric(horizontal: pad),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(h),
          border: Border.all(
            color: _accent.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(_icon, color: _accentDeep, size: iconSize),
            SizedBox(width: dense ? 5 : 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _label,
                  style: TextStyle(
                    color: _accentDeep,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    height: 1.0,
                  ),
                ),
                if (!dense) ...[
                  const SizedBox(height: 1),
                  Text(
                    _caption,
                    style: TextStyle(
                      color: _accentDeep.withValues(alpha: 0.72),
                      fontSize: captionSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
