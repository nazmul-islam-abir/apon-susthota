import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'data/bd_food_library.dart';
import 'data/food_image_links.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart' as api;
import 'services/auth_service.dart';
import 'services/hive_store.dart';
import 'services/settings_prefs.dart';
import 'widgets/food_image.dart';
import 'widgets/gradient_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HiveStore.instance.init();
  await AuthService.instance.hydrate();
  await SettingsPrefs.hydrateNotifiers();

  final phone = AuthService.instance.phone;
  if (phone != null && phone.isNotEmpty) {
    await HiveStore.instance.preOpenUser(phone);
  }

  seedFoodImageRegistry(
    _allFoodsAsLegacy(),
    FoodImageLinks.links,
  );

  runApp(const AmarDietApp());
}

List<api.FoodItem> _allFoodsAsLegacy() {
  return [
    for (final f in BdFoodLibrary.all)
      api.FoodItem(
        id: f.id,
        nameEn: f.nameEn,
        nameBn: f.nameBn,
        category: f.category,
        servingG: f.servingG,
        kcalPerServing: f.kcalPerServing,
        proteinG: f.proteinG,
        carbsG: f.carbsG,
        fatG: f.fatG,
        fiberG: f.fiberG,
      ),
  ];
}

class AmarDietApp extends StatelessWidget {
  const AmarDietApp({super.key});

  ThemeData _light() => buildAppTheme();

  ThemeData _dark() {
    final base = buildAppTheme();
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1F1A),
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: const Color(0xFF102A23),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsPrefs.darkModeNotifier,
      builder: (_, dark, __) {
        return MaterialApp(
          title: 'Amar Diet',
          debugShowCheckedModeBanner: false,
          theme: _light(),
          darkTheme: _dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => GradientBackground(child: child!),
          home: const SplashScreen(),
        );
      },
    );
  }
}
