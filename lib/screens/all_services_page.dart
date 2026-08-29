/// আপন সুস্থতা — All Services (Service Hub) redesigned.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../widgets/back_scaffold.dart';
import '../widgets/mono_widgets.dart';
import 'analytics_screen.dart';
import 'ai_chat_screen.dart';
import 'doctor_report_screen.dart';
import 'meal_plan_screen.dart';
import 'medicine_screen.dart';
import 'profile_screen.dart';
import 'water_screen.dart';
import 'workout_screen.dart';

class AllServicesPage extends StatelessWidget {
  const AllServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            _buildHero(context),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            _buildGrid(context),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final dateStr = DateFormat('MMMM d, yyyy', 'en').format(DateTime.now());

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'সব পরিষেবা',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          ),
                        ),
                        // Removed Hamburger menu and duplicate elements
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text(
                        'আপনার প্রয়োজনীয়\nসব সেবা এখানে',
                        style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
                        child: const Text('অন্বেষণ করুন', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final cards = [
      _ServiceDef('খাবার', 'Meal Plan', Icons.restaurant_rounded, () => _go(context, const MealPlanScreen())),
      _ServiceDef('ব্যায়াম', 'Workout', Icons.fitness_center_rounded, () => _go(context, const WorkoutScreen()), highlighted: true),
      _ServiceDef('ওষুধ', 'Medicine', Icons.medical_services_rounded, () => _go(context, const MedicineScreen())),
      _ServiceDef('বিশ্লেষণ', 'Analytics', Icons.insights_rounded, () => _go(context, const AnalyticsScreen())),
      _ServiceDef('পানি', 'Water', Icons.water_drop_rounded, () => _go(context, const WaterScreen())),
      _ServiceDef('প্রোফাইল', 'Profile', Icons.person_rounded, () => _go(context, const ProfileScreen())),
      _ServiceDef('AI সহকারী', 'Apon AI', Icons.auto_awesome_rounded, () => _go(context, const AiChatScreen())),
      _ServiceDef('রিপোর্ট', 'Report', Icons.assignment_rounded, () => _go(context, const DoctorReportScreen())),
    ];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ServiceCard(def: cards[i]),
          childCount: cards.length,
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget s) {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => s));
  }
}

class _ServiceDef {
  final String bn, en;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  _ServiceDef(this.bn, this.en, this.icon, this.onTap, {this.highlighted = false});
}

class _ServiceCard extends StatelessWidget {
  final _ServiceDef def;
  const _ServiceCard({required this.def});

  @override
  Widget build(BuildContext context) {
    final bg = def.highlighted ? AppColors.svcAccentGreenBright : Colors.white;
    final fg = def.highlighted ? AppColors.svcHero : AppColors.svcHero;

    return InkWell(
      onTap: def.onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(def.icon, color: fg, size: 32),
            const SizedBox(height: 14),
            Text(def.bn, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: fg, height: 1.1)),
            const SizedBox(height: 2),
            Text(def.en, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: def.highlighted ? fg.withValues(alpha: 0.7) : AppColors.smoke)),
          ],
        ),
      ),
    );
  }
}
