import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('অন্বেষণ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const Center(
        child: Text(
          'অন্বেষণ পাতাটি শীঘ্রই আসছে...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
