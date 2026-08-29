import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In bn, this message translates to:
  /// **'আপন সুস্থতা'**
  String get appTitle;

  /// No description provided for @helloGreeting.
  ///
  /// In bn, this message translates to:
  /// **'হ্যালো,'**
  String get helloGreeting;

  /// No description provided for @friendName.
  ///
  /// In bn, this message translates to:
  /// **'Friend'**
  String get friendName;

  /// No description provided for @yourLocation.
  ///
  /// In bn, this message translates to:
  /// **'আপনার অবস্থান'**
  String get yourLocation;

  /// No description provided for @languageBn.
  ///
  /// In bn, this message translates to:
  /// **'বাংলা (Bangla)'**
  String get languageBn;

  /// No description provided for @languageEn.
  ///
  /// In bn, this message translates to:
  /// **'English (ইংরেজি)'**
  String get languageEn;

  /// No description provided for @searchHint.
  ///
  /// In bn, this message translates to:
  /// **'পরিসেবা খুঁজুন...'**
  String get searchHint;

  /// No description provided for @heroHeadline.
  ///
  /// In bn, this message translates to:
  /// **'আপনার সুস্থতার সমাধান,\nএখন এক ট্যাপেই!'**
  String get heroHeadline;

  /// No description provided for @heroSubhead.
  ///
  /// In bn, this message translates to:
  /// **'সহজ, দ্রুত এবং নির্ভরযোগ্য\nসবকিছু আপনার হাতের নাগালে'**
  String get heroSubhead;

  /// No description provided for @exploreCta.
  ///
  /// In bn, this message translates to:
  /// **'অন্বেষণ করুন'**
  String get exploreCta;

  /// No description provided for @sectionCategories.
  ///
  /// In bn, this message translates to:
  /// **'পরিষেবা বিভাগ'**
  String get sectionCategories;

  /// No description provided for @sectionCategoriesSub.
  ///
  /// In bn, this message translates to:
  /// **'আপনার প্রয়োজনীয় সব সেবা'**
  String get sectionCategoriesSub;

  /// No description provided for @sectionPopular.
  ///
  /// In bn, this message translates to:
  /// **'জনপ্রিয় পরিষেবা'**
  String get sectionPopular;

  /// No description provided for @sectionPopularSub.
  ///
  /// In bn, this message translates to:
  /// **'সচরাচর ব্যবহৃত সেবাগুলো'**
  String get sectionPopularSub;

  /// No description provided for @sectionHealth.
  ///
  /// In bn, this message translates to:
  /// **'স্বাস্থ্যের অবস্থা'**
  String get sectionHealth;

  /// No description provided for @sectionHealthSub.
  ///
  /// In bn, this message translates to:
  /// **'আপনার বর্তমান শারীরিক তথ্য'**
  String get sectionHealthSub;

  /// No description provided for @seeAll.
  ///
  /// In bn, this message translates to:
  /// **'সব দেখুন'**
  String get seeAll;

  /// No description provided for @serviceWater.
  ///
  /// In bn, this message translates to:
  /// **'পানি'**
  String get serviceWater;

  /// No description provided for @serviceWaterSub.
  ///
  /// In bn, this message translates to:
  /// **'পানির ট্র্যাকার'**
  String get serviceWaterSub;

  /// No description provided for @serviceCare.
  ///
  /// In bn, this message translates to:
  /// **'পরিচর্যা'**
  String get serviceCare;

  /// No description provided for @serviceCareSub.
  ///
  /// In bn, this message translates to:
  /// **'সংযুক্ত ব্যক্তি'**
  String get serviceCareSub;

  /// No description provided for @serviceFood.
  ///
  /// In bn, this message translates to:
  /// **'খাবার'**
  String get serviceFood;

  /// No description provided for @serviceFoodSub.
  ///
  /// In bn, this message translates to:
  /// **'খাবারের পরিকল্পনা'**
  String get serviceFoodSub;

  /// No description provided for @serviceWorkout.
  ///
  /// In bn, this message translates to:
  /// **'ব্যায়াম'**
  String get serviceWorkout;

  /// No description provided for @serviceWorkoutSub.
  ///
  /// In bn, this message translates to:
  /// **'ব্যায়ামের রুটিন'**
  String get serviceWorkoutSub;

  /// No description provided for @popularMeal.
  ///
  /// In bn, this message translates to:
  /// **'খাবার লগিং'**
  String get popularMeal;

  /// No description provided for @popularMealSub.
  ///
  /// In bn, this message translates to:
  /// **'প্রতিদিনের খাবারের তালিকা'**
  String get popularMealSub;

  /// No description provided for @popularWorkout.
  ///
  /// In bn, this message translates to:
  /// **'ব্যায়াম পরিকল্পনা'**
  String get popularWorkout;

  /// No description provided for @popularWorkoutSub.
  ///
  /// In bn, this message translates to:
  /// **'আপনার শারীরিক কসরত'**
  String get popularWorkoutSub;

  /// No description provided for @popularMedicine.
  ///
  /// In bn, this message translates to:
  /// **'ওষুধের রিমাইন্ডার'**
  String get popularMedicine;

  /// No description provided for @popularMedicineSub.
  ///
  /// In bn, this message translates to:
  /// **'সময়মতো ওষুধ সেবন'**
  String get popularMedicineSub;

  /// No description provided for @popularAnalytics.
  ///
  /// In bn, this message translates to:
  /// **'স্বাস্থ্য বিশ্লেষণ'**
  String get popularAnalytics;

  /// No description provided for @popularAnalyticsSub.
  ///
  /// In bn, this message translates to:
  /// **'আপনার উন্নতির রিপোর্ট'**
  String get popularAnalyticsSub;

  /// No description provided for @popularWater.
  ///
  /// In bn, this message translates to:
  /// **'পানি ট্র্যাকার'**
  String get popularWater;

  /// No description provided for @popularWaterSub.
  ///
  /// In bn, this message translates to:
  /// **'শরীর হাইড্রেটেড রাখুন'**
  String get popularWaterSub;

  /// No description provided for @popularProfile.
  ///
  /// In bn, this message translates to:
  /// **'প্রোফাইল তথ্য'**
  String get popularProfile;

  /// No description provided for @popularProfileSub.
  ///
  /// In bn, this message translates to:
  /// **'আপনার ব্যক্তিগত সেটিংস'**
  String get popularProfileSub;

  /// No description provided for @priceFree.
  ///
  /// In bn, this message translates to:
  /// **'ফ্রি'**
  String get priceFree;

  /// No description provided for @reviewsLabel.
  ///
  /// In bn, this message translates to:
  /// **'রিভিউ'**
  String get reviewsLabel;

  /// No description provided for @loadFailed.
  ///
  /// In bn, this message translates to:
  /// **'ডেটা লোড করা যাচ্ছে না'**
  String get loadFailed;

  /// No description provided for @retry.
  ///
  /// In bn, this message translates to:
  /// **'আবার চেষ্টা করুন'**
  String get retry;

  /// No description provided for @navDashboard.
  ///
  /// In bn, this message translates to:
  /// **'ড্যাশবোর্ড'**
  String get navDashboard;

  /// No description provided for @navMeal.
  ///
  /// In bn, this message translates to:
  /// **'আজ'**
  String get navMeal;

  /// No description provided for @navWorkout.
  ///
  /// In bn, this message translates to:
  /// **'ব্যায়াম'**
  String get navWorkout;

  /// No description provided for @navAnalytics.
  ///
  /// In bn, this message translates to:
  /// **'বিশ্লেষণ'**
  String get navAnalytics;

  /// No description provided for @navAi.
  ///
  /// In bn, this message translates to:
  /// **'AI সহকারী'**
  String get navAi;

  /// No description provided for @moodBannerTitle.
  ///
  /// In bn, this message translates to:
  /// **'আজকের মেজাজ'**
  String get moodBannerTitle;

  /// No description provided for @moodBannerSubtitle.
  ///
  /// In bn, this message translates to:
  /// **'২ সেকেন্ড ধরে রাখুন'**
  String get moodBannerSubtitle;

  /// No description provided for @moodLoggedPrefix.
  ///
  /// In bn, this message translates to:
  /// **'আজ লগ করেছেন:'**
  String get moodLoggedPrefix;

  /// No description provided for @moodEditTooltip.
  ///
  /// In bn, this message translates to:
  /// **'আবার লগ করুন'**
  String get moodEditTooltip;

  /// No description provided for @moodSheetTitle.
  ///
  /// In bn, this message translates to:
  /// **'দৈনিক স্বাস্থ্য তথ্য'**
  String get moodSheetTitle;

  /// No description provided for @sleepHoursLabel.
  ///
  /// In bn, this message translates to:
  /// **'ঘুমের ঘণ্টা'**
  String get sleepHoursLabel;

  /// No description provided for @energyLevelLabel.
  ///
  /// In bn, this message translates to:
  /// **'শক্তির মাত্রা'**
  String get energyLevelLabel;

  /// No description provided for @stressLevelLabel.
  ///
  /// In bn, this message translates to:
  /// **'মানসিক চাপ'**
  String get stressLevelLabel;

  /// No description provided for @symptomsLabel.
  ///
  /// In bn, this message translates to:
  /// **'উপসর্গ (ঐচ্ছিক)'**
  String get symptomsLabel;

  /// No description provided for @symptomsHint.
  ///
  /// In bn, this message translates to:
  /// **'আজ কোনো শারীরিক সমস্যা?'**
  String get symptomsHint;

  /// No description provided for @moodSavedToast.
  ///
  /// In bn, this message translates to:
  /// **'আজকের মেজাজ সংরক্ষিত হয়েছে'**
  String get moodSavedToast;

  /// No description provided for @moodSavingToast.
  ///
  /// In bn, this message translates to:
  /// **'সংরক্ষণ হচ্ছে...'**
  String get moodSavingToast;

  /// No description provided for @moodReminderPrompt.
  ///
  /// In bn, this message translates to:
  /// **'দিনের শেষে নিজের যত্ন নিন — আজ কেমন আছেন?'**
  String get moodReminderPrompt;

  /// No description provided for @moodReminderClose.
  ///
  /// In bn, this message translates to:
  /// **'পরে হবে'**
  String get moodReminderClose;

  /// No description provided for @moodSaveButton.
  ///
  /// In bn, this message translates to:
  /// **'সংরক্ষণ করুন'**
  String get moodSaveButton;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
