import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'mono_widgets.dart';

/// Tap-to-edit metric row used on the profile screen.
///
/// Shows a label, current value, and a pencil hint. Tapping opens a
/// bottom sheet with a labeled text field and validation; on save the
/// parent is notified through [onChanged].
class InlineEditField extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final String? hint;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String> onChanged;

  /// Optional accent for the value text. Use [AppColors.danger] for
  /// out-of-range values like HbA1c > 8.5% so the user sees the warning
  /// before they tap.
  final Color? valueColor;

  const InlineEditField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.valueColor,
  });

  Future<void> _openSheet(BuildContext context) async {
    final controller = TextEditingController(text: value);
    final formKey = GlobalKey<FormState>();
    String? localError;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                if (hint != null)
                  Text(
                    hint!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: keyboardType,
                  inputFormatters: keyboardType ==
                          const TextInputType.numberWithOptions(decimal: true)
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                      : null,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    suffixText: suffix,
                    suffixStyle: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textMuted,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.cyan, width: 1.5),
                    ),
                  ),
                  validator: (v) {
                    final e = validator?.call(v);
                    localError = e;
                    return e;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                              color: AppColors.lineStrong, width: 1.2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          'বাতিল',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.of(ctx).pop(controller.text.trim());
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          'সংরক্ষণ',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.onAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && result.isNotEmpty && result != value) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            value.isEmpty ? '—' : value,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: valueColor ?? AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (suffix != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            suffix!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact toggle row for binary conditions (CKD, Heart, Anemia, Insulin).
/// Uses the same tap-to-open sheet pattern but with Yes/No buttons.
class InlineToggleField extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? detail;

  const InlineToggleField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showModalBottomSheet<bool>(
            context: context,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (ctx) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                    if (detail != null) ...[
                      const SizedBox(height: 6),
                      Text(detail!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted)),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                  color: AppColors.lineStrong, width: 1.2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('না',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: AppColors.cyan,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('হ্যাঁ',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.onAccent,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
          if (picked != null && picked != value) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          value
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: value
                              ? AppColors.mint
                              : AppColors.textDim,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          value ? 'হ্যাঁ' : 'না',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color:
                                value ? AppColors.text : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section card with a heading and a body for inline-edit fields.
class InlineEditCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const InlineEditCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.cyan),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.line, height: 12),
          ...children,
        ],
      ),
    );
  }
}