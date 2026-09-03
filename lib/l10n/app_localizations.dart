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

  /// No description provided for @exitMessage.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাপ থেকে বের হতে চান?'**
  String get exitMessage;

  /// No description provided for @exitTitle.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাপ বন্ধ করবেন?'**
  String get exitTitle;

  /// No description provided for @exitConfirm.
  ///
  /// In bn, this message translates to:
  /// **'বের হন'**
  String get exitConfirm;

  /// No description provided for @exitCancel.
  ///
  /// In bn, this message translates to:
  /// **'থাকুন'**
  String get exitCancel;

  /// No description provided for @backTooltip.
  ///
  /// In bn, this message translates to:
  /// **'ফিরে যান'**
  String get backTooltip;

  /// No description provided for @pendingActionIntro.
  ///
  /// In bn, this message translates to:
  /// **'আমি যা করতে চাই:'**
  String get pendingActionIntro;

  /// No description provided for @pendingActionConfirm.
  ///
  /// In bn, this message translates to:
  /// **'করুন'**
  String get pendingActionConfirm;

  /// No description provided for @pendingActionCancel.
  ///
  /// In bn, this message translates to:
  /// **'বাতিল'**
  String get pendingActionCancel;

  /// No description provided for @pendingActionDetails.
  ///
  /// In bn, this message translates to:
  /// **'বিস্তারিত দেখুন'**
  String get pendingActionDetails;

  /// No description provided for @pendingActionCollapse.
  ///
  /// In bn, this message translates to:
  /// **'বন্ধ করুন'**
  String get pendingActionCollapse;

  /// No description provided for @pendingActionFallbackError.
  ///
  /// In bn, this message translates to:
  /// **'কিছু একটা ভুল হয়েছে — আবার চেষ্টা করুন।'**
  String get pendingActionFallbackError;

  /// No description provided for @toolUndone.
  ///
  /// In bn, this message translates to:
  /// **'ফিরিয়ে আনা হয়েছে'**
  String get toolUndone;

  /// No description provided for @toolCancelled.
  ///
  /// In bn, this message translates to:
  /// **'বাতিল করা হয়েছে'**
  String get toolCancelled;

  /// No description provided for @toolUndoButton.
  ///
  /// In bn, this message translates to:
  /// **'ফিরিয়ে আনুন ({seconds})'**
  String toolUndoButton(Object seconds);

  /// No description provided for @toolUndoExpired.
  ///
  /// In bn, this message translates to:
  /// **'Undo window বন্ধ হয়ে গেছে।'**
  String get toolUndoExpired;

  /// No description provided for @restrictedFoodsTitle.
  ///
  /// In bn, this message translates to:
  /// **'এড়িয়ে চলা উচিত এমন খাবার'**
  String get restrictedFoodsTitle;

  /// No description provided for @restrictedFoodsBlurb.
  ///
  /// In bn, this message translates to:
  /// **'আপনার বর্তমান স্বাস্থ্য অবস্থা অনুযায়ী নিচের খাবারগুলো সীমিত বা এড়িয়ে চলা উচিত।'**
  String get restrictedFoodsBlurb;

  /// No description provided for @restrictedFoodsMore.
  ///
  /// In bn, this message translates to:
  /// **'আরও {count}টি খাবার রয়েছে — সব দেখতে প্রোফাইল সম্পাদনা করুন।'**
  String restrictedFoodsMore(Object count);

  /// No description provided for @restrictedFoodsEmpty.
  ///
  /// In bn, this message translates to:
  /// **'আপনার বর্তমান স্বাস্থ্য তথ্য অনুযায়ী নির্দিষ্ট কোনো নিষিদ্ধ খাবার নেই। চিকিৎসকের পরামর্শ অনুযায়ী এগিয়ে যান।'**
  String get restrictedFoodsEmpty;

  /// No description provided for @classificationTitle.
  ///
  /// In bn, this message translates to:
  /// **'আপনার বর্তমান শ্রেণিবিন্যাস'**
  String get classificationTitle;

  /// No description provided for @classificationGlucose.
  ///
  /// In bn, this message translates to:
  /// **'গ্লুকোজ'**
  String get classificationGlucose;

  /// No description provided for @classificationBmi.
  ///
  /// In bn, this message translates to:
  /// **'BMI'**
  String get classificationBmi;

  /// No description provided for @classificationBp.
  ///
  /// In bn, this message translates to:
  /// **'রক্তচাপ'**
  String get classificationBp;

  /// No description provided for @classificationDailyTargets.
  ///
  /// In bn, this message translates to:
  /// **'দৈনিক লক্ষ্যমাত্রা'**
  String get classificationDailyTargets;

  /// No description provided for @classificationKcal.
  ///
  /// In bn, this message translates to:
  /// **'ক্যালোরি'**
  String get classificationKcal;

  /// No description provided for @classificationCarb.
  ///
  /// In bn, this message translates to:
  /// **'কার্ব'**
  String get classificationCarb;

  /// No description provided for @classificationProtein.
  ///
  /// In bn, this message translates to:
  /// **'প্রোটিন'**
  String get classificationProtein;

  /// No description provided for @classificationFat.
  ///
  /// In bn, this message translates to:
  /// **'চর্বি'**
  String get classificationFat;

  /// No description provided for @classificationSodium.
  ///
  /// In bn, this message translates to:
  /// **'সোডিয়াম সর্বোচ্চ'**
  String get classificationSodium;

  /// No description provided for @classificationCarbPerMeal.
  ///
  /// In bn, this message translates to:
  /// **'এক বেলায় কার্ব'**
  String get classificationCarbPerMeal;

  /// No description provided for @classificationValueKcal.
  ///
  /// In bn, this message translates to:
  /// **'{value} kcal'**
  String classificationValueKcal(Object value);

  /// No description provided for @classificationValueG.
  ///
  /// In bn, this message translates to:
  /// **'{value} g'**
  String classificationValueG(Object value);

  /// No description provided for @classificationValueMg.
  ///
  /// In bn, this message translates to:
  /// **'{value} mg'**
  String classificationValueMg(Object value);

  /// No description provided for @tierGood.
  ///
  /// In bn, this message translates to:
  /// **'ভালো'**
  String get tierGood;

  /// No description provided for @tierModerate.
  ///
  /// In bn, this message translates to:
  /// **'মাঝারি'**
  String get tierModerate;

  /// No description provided for @tierPoor.
  ///
  /// In bn, this message translates to:
  /// **'খারাপ'**
  String get tierPoor;

  /// No description provided for @tierUnderweight.
  ///
  /// In bn, this message translates to:
  /// **'কম ওজন'**
  String get tierUnderweight;

  /// No description provided for @tierNormal.
  ///
  /// In bn, this message translates to:
  /// **'স্বাভাবিক'**
  String get tierNormal;

  /// No description provided for @tierOverweight.
  ///
  /// In bn, this message translates to:
  /// **'বেশি ওজন'**
  String get tierOverweight;

  /// No description provided for @tierObese.
  ///
  /// In bn, this message translates to:
  /// **'স্থূল'**
  String get tierObese;

  /// No description provided for @tierElevated.
  ///
  /// In bn, this message translates to:
  /// **'উচ্চ'**
  String get tierElevated;

  /// No description provided for @tierStage1.
  ///
  /// In bn, this message translates to:
  /// **'পর্যায় ১'**
  String get tierStage1;

  /// No description provided for @tierStage2.
  ///
  /// In bn, this message translates to:
  /// **'পর্যায় ২'**
  String get tierStage2;

  /// No description provided for @tierUnknown.
  ///
  /// In bn, this message translates to:
  /// **'অজানা'**
  String get tierUnknown;

  /// No description provided for @recommendationsTitle.
  ///
  /// In bn, this message translates to:
  /// **'ব্যক্তিগত পরামর্শ'**
  String get recommendationsTitle;

  /// No description provided for @clinicalSnapshotTitle.
  ///
  /// In bn, this message translates to:
  /// **'স্বাস্থ্যের বর্তমান অবস্থা'**
  String get clinicalSnapshotTitle;

  /// No description provided for @clinicalSnapshotWarnings.
  ///
  /// In bn, this message translates to:
  /// **'সতর্কতা'**
  String get clinicalSnapshotWarnings;

  /// No description provided for @clinicalSnapshotFood.
  ///
  /// In bn, this message translates to:
  /// **'খাদ্য'**
  String get clinicalSnapshotFood;

  /// No description provided for @macroCarb.
  ///
  /// In bn, this message translates to:
  /// **'কার্ব'**
  String get macroCarb;

  /// No description provided for @macroCarbValue.
  ///
  /// In bn, this message translates to:
  /// **'{value} গ্রাম'**
  String macroCarbValue(Object value);

  /// No description provided for @macroKcal.
  ///
  /// In bn, this message translates to:
  /// **'ক্যালোরি'**
  String get macroKcal;

  /// No description provided for @macroSodium.
  ///
  /// In bn, this message translates to:
  /// **'সোডিয়াম'**
  String get macroSodium;

  /// No description provided for @macroSodiumValue.
  ///
  /// In bn, this message translates to:
  /// **'{value} মিগ্রা'**
  String macroSodiumValue(Object value);

  /// No description provided for @foodPrefOmnivore.
  ///
  /// In bn, this message translates to:
  /// **'সব খাবার'**
  String get foodPrefOmnivore;

  /// No description provided for @foodPrefVegetarian.
  ///
  /// In bn, this message translates to:
  /// **'নিরামিষ'**
  String get foodPrefVegetarian;

  /// No description provided for @foodPrefFishOnly.
  ///
  /// In bn, this message translates to:
  /// **'শুধু মাছ'**
  String get foodPrefFishOnly;

  /// No description provided for @foodPrefNoBeef.
  ///
  /// In bn, this message translates to:
  /// **'গরুর মাংস ছাড়া'**
  String get foodPrefNoBeef;

  /// No description provided for @caretakerNavPatients.
  ///
  /// In bn, this message translates to:
  /// **'রোগী'**
  String get caretakerNavPatients;

  /// No description provided for @caretakerNavHome.
  ///
  /// In bn, this message translates to:
  /// **'হোম'**
  String get caretakerNavHome;

  /// No description provided for @caretakerNavToday.
  ///
  /// In bn, this message translates to:
  /// **'আজ'**
  String get caretakerNavToday;

  /// No description provided for @caretakerNavInbox.
  ///
  /// In bn, this message translates to:
  /// **'ইনবক্স'**
  String get caretakerNavInbox;

  /// No description provided for @caretakerNavSearch.
  ///
  /// In bn, this message translates to:
  /// **'খোঁজা'**
  String get caretakerNavSearch;

  /// No description provided for @rolePatient.
  ///
  /// In bn, this message translates to:
  /// **'রোগী'**
  String get rolePatient;

  /// No description provided for @roleCaregiver.
  ///
  /// In bn, this message translates to:
  /// **'কেয়ারগিভার'**
  String get roleCaregiver;

  /// No description provided for @rolePatientCaption.
  ///
  /// In bn, this message translates to:
  /// **'ব্যক্তিগত মোড'**
  String get rolePatientCaption;

  /// No description provided for @roleCaregiverCaption.
  ///
  /// In bn, this message translates to:
  /// **'অবলোকন মোড'**
  String get roleCaregiverCaption;

  /// No description provided for @roleChipSemantics.
  ///
  /// In bn, this message translates to:
  /// **'বর্তমান ভূমিকা: {role}'**
  String roleChipSemantics(Object role);

  /// No description provided for @drawerProfile.
  ///
  /// In bn, this message translates to:
  /// **'প্রোফাইল'**
  String get drawerProfile;

  /// No description provided for @drawerProfileSub.
  ///
  /// In bn, this message translates to:
  /// **'আমার তথ্য ও সেটিংস'**
  String get drawerProfileSub;

  /// No description provided for @drawerMedicine.
  ///
  /// In bn, this message translates to:
  /// **'মেডিসিন'**
  String get drawerMedicine;

  /// No description provided for @drawerMedicineSub.
  ///
  /// In bn, this message translates to:
  /// **'ওষুধের রিমাইন্ডার ও ট্র্যাকার'**
  String get drawerMedicineSub;

  /// No description provided for @drawerWater.
  ///
  /// In bn, this message translates to:
  /// **'পানি'**
  String get drawerWater;

  /// No description provided for @drawerWaterSub.
  ///
  /// In bn, this message translates to:
  /// **'দৈনিক লক্ষ্য ও ট্র্যাকার'**
  String get drawerWaterSub;

  /// No description provided for @drawerDoctorReport.
  ///
  /// In bn, this message translates to:
  /// **'ডাক্তারের রিপোর্ট'**
  String get drawerDoctorReport;

  /// No description provided for @drawerDoctorReportSub.
  ///
  /// In bn, this message translates to:
  /// **'৩০ দিনের চক্র ও PDF'**
  String get drawerDoctorReportSub;

  /// No description provided for @drawerMyCaretakers.
  ///
  /// In bn, this message translates to:
  /// **'আমার কেয়ারটেকার'**
  String get drawerMyCaretakers;

  /// No description provided for @drawerMyCaretakersSub.
  ///
  /// In bn, this message translates to:
  /// **'কে কে আপনাকে পর্যবেক্ষণ করছেন'**
  String get drawerMyCaretakersSub;

  /// No description provided for @drawerLogout.
  ///
  /// In bn, this message translates to:
  /// **'লগআউট'**
  String get drawerLogout;

  /// No description provided for @drawerLogoutSub.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাকাউন্ট থেকে বের হোন'**
  String get drawerLogoutSub;

  /// No description provided for @drawerViewProfile.
  ///
  /// In bn, this message translates to:
  /// **'আমার প্রোফাইল দেখুন →'**
  String get drawerViewProfile;

  /// No description provided for @drawerFriend.
  ///
  /// In bn, this message translates to:
  /// **'বন্ধু'**
  String get drawerFriend;

  /// No description provided for @drawerInitial.
  ///
  /// In bn, this message translates to:
  /// **'আ'**
  String get drawerInitial;

  /// No description provided for @drawerAppVersion.
  ///
  /// In bn, this message translates to:
  /// **'Version {version}'**
  String drawerAppVersion(Object version);

  /// No description provided for @videoLabelGuide.
  ///
  /// In bn, this message translates to:
  /// **'ভিডিও গাইড'**
  String get videoLabelGuide;

  /// No description provided for @videoUnavailable.
  ///
  /// In bn, this message translates to:
  /// **'ভিডিও লোড হচ্ছে না'**
  String get videoUnavailable;

  /// No description provided for @videoComingSoonTitle.
  ///
  /// In bn, this message translates to:
  /// **'ভিডিও শীঘ্রই আসছে'**
  String get videoComingSoonTitle;

  /// No description provided for @videoComingSoonSub.
  ///
  /// In bn, this message translates to:
  /// **'প্রথমে ব্যায়ামের বিবরণ পড়ুন'**
  String get videoComingSoonSub;

  /// No description provided for @videoNoneTitle.
  ///
  /// In bn, this message translates to:
  /// **'ভিডিও নেই'**
  String get videoNoneTitle;

  /// No description provided for @videoNoneSub.
  ///
  /// In bn, this message translates to:
  /// **'এই ব্যায়ামের ভিডিও যোগ হয়নি'**
  String get videoNoneSub;

  /// No description provided for @videoTapToPlay.
  ///
  /// In bn, this message translates to:
  /// **'ট্যাপ করে চালু করুন'**
  String get videoTapToPlay;

  /// No description provided for @videoMuted.
  ///
  /// In bn, this message translates to:
  /// **'নীরব'**
  String get videoMuted;

  /// No description provided for @videoSoundOn.
  ///
  /// In bn, this message translates to:
  /// **'শব্দ চালু'**
  String get videoSoundOn;

  /// No description provided for @videoPlay.
  ///
  /// In bn, this message translates to:
  /// **'চালু করুন'**
  String get videoPlay;

  /// No description provided for @videoPause.
  ///
  /// In bn, this message translates to:
  /// **'বিরতি'**
  String get videoPause;

  /// No description provided for @videoSkip.
  ///
  /// In bn, this message translates to:
  /// **'এড়িয়ে যান'**
  String get videoSkip;

  /// No description provided for @videoUrlMissing.
  ///
  /// In bn, this message translates to:
  /// **'ভিডিওর লিঙ্ক খুঁজে পাওয়া যায়নি'**
  String get videoUrlMissing;

  /// No description provided for @videoPlaybackError.
  ///
  /// In bn, this message translates to:
  /// **'ভিডিও চালানো যাচ্ছে না — স্টোরেজ ফাইল বা সাইনড URL সমস্যা হতে পারে'**
  String get videoPlaybackError;

  /// No description provided for @splashBrandBn.
  ///
  /// In bn, this message translates to:
  /// **'আপন সুস্থতা'**
  String get splashBrandBn;

  /// No description provided for @setupErrorOverline.
  ///
  /// In bn, this message translates to:
  /// **'সেটআপ সমস্যা'**
  String get setupErrorOverline;

  /// No description provided for @setupErrorHeadline.
  ///
  /// In bn, this message translates to:
  /// **'Supabase সংযোগ হয়নি'**
  String get setupErrorHeadline;

  /// No description provided for @setupErrorUnknown.
  ///
  /// In bn, this message translates to:
  /// **'অজানা সেটআপ ত্রুটি — লগ দেখুন।'**
  String get setupErrorUnknown;

  /// No description provided for @setupErrorStepsTitle.
  ///
  /// In bn, this message translates to:
  /// **'কী করবেন'**
  String get setupErrorStepsTitle;

  /// No description provided for @setupErrorStep1Title.
  ///
  /// In bn, this message translates to:
  /// **'.env ফাইল তৈরি করুন'**
  String get setupErrorStep1Title;

  /// No description provided for @setupErrorStep1Body.
  ///
  /// In bn, this message translates to:
  /// **'প্রজেক্টের রুটে .env.example কপি করে .env নামে সেভ করুন।'**
  String get setupErrorStep1Body;

  /// No description provided for @setupErrorStep2Title.
  ///
  /// In bn, this message translates to:
  /// **'Supabase কী বসান'**
  String get setupErrorStep2Title;

  /// No description provided for @setupErrorStep2Body.
  ///
  /// In bn, this message translates to:
  /// **'SUPABASE_URL ও SUPABASE_ANON_KEY পূরণ করুন (Supabase Dashboard → Project Settings → API)।'**
  String get setupErrorStep2Body;

  /// No description provided for @setupErrorStep3Title.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাপ পুনরায় চালু করুন'**
  String get setupErrorStep3Title;

  /// No description provided for @setupErrorStep3Body.
  ///
  /// In bn, this message translates to:
  /// **'flutter run আবার চালালে সেটআপ স্ক্রিন আর দেখাবে না।'**
  String get setupErrorStep3Body;

  /// No description provided for @setupErrorCopyButton.
  ///
  /// In bn, this message translates to:
  /// **'কপি: SUPABASE_URL দরকার'**
  String get setupErrorCopyButton;

  /// No description provided for @setupErrorCopied.
  ///
  /// In bn, this message translates to:
  /// **'ক্লিপবোর্ডে কপি হয়েছে।'**
  String get setupErrorCopied;

  /// No description provided for @roleSelectTitle.
  ///
  /// In bn, this message translates to:
  /// **'আপনি কে?'**
  String get roleSelectTitle;

  /// No description provided for @roleSelectHeadline.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাকাউন্টের ধরন বেছে নিন'**
  String get roleSelectHeadline;

  /// No description provided for @roleSelectBlurb.
  ///
  /// In bn, this message translates to:
  /// **'আপনি কি ডায়াবেটিস রোগী, নাকি পরিবারের কেউ অন্যের যত্ন নিচ্ছেন?'**
  String get roleSelectBlurb;

  /// No description provided for @roleCardPatientTitle.
  ///
  /// In bn, this message translates to:
  /// **'রোগী'**
  String get roleCardPatientTitle;

  /// No description provided for @roleCardPatientEn.
  ///
  /// In bn, this message translates to:
  /// **'Patient'**
  String get roleCardPatientEn;

  /// No description provided for @roleCardPatientDesc.
  ///
  /// In bn, this message translates to:
  /// **'আমি নিজে ডায়াবেটিস ম্যানেজ করছি। নিজের খাবার, ওষুধ ও ব্যায়ামের প্ল্যান দেখব।'**
  String get roleCardPatientDesc;

  /// No description provided for @roleCardCaregiverTitle.
  ///
  /// In bn, this message translates to:
  /// **'পরিচর্যাকারী'**
  String get roleCardCaregiverTitle;

  /// No description provided for @roleCardCaregiverEn.
  ///
  /// In bn, this message translates to:
  /// **'Caregiver'**
  String get roleCardCaregiverEn;

  /// No description provided for @roleCardCaregiverDesc.
  ///
  /// In bn, this message translates to:
  /// **'আমি অন্যের (বাবা/মা/স্বামী/স্ত্রী) যত্ন নিই। তাঁর খাবার ও ওষুধ খেয়াল রাখব — কোনো বিশ্লেষণ বা প্ল্যান সম্পাদনা করব না।'**
  String get roleCardCaregiverDesc;

  /// No description provided for @roleSelectRelationshipOverline.
  ///
  /// In bn, this message translates to:
  /// **'আপনার সম্পর্ক'**
  String get roleSelectRelationshipOverline;

  /// No description provided for @roleSelectRelationshipHint.
  ///
  /// In bn, this message translates to:
  /// **'যেমন: ছেলে, মেয়ে, স্বামী, স্ত্রী, পরিচর্যাকারী'**
  String get roleSelectRelationshipHint;

  /// No description provided for @roleSelectClinicalNote.
  ///
  /// In bn, this message translates to:
  /// **'ক্লিনিক্যাল নীতি: পরিচর্যাকারী কখনও রোগীর বিশ্লেষণ, খাবারের প্ল্যান বা প্রোফাইল সম্পাদনা করতে পারবেন না — শুধু দেখতে ও প্রয়োজনে খাবার/ওষুধ লগ করতে পারবেন।'**
  String get roleSelectClinicalNote;

  /// No description provided for @roleSelectSaving.
  ///
  /// In bn, this message translates to:
  /// **'সংরক্ষণ হচ্ছে…'**
  String get roleSelectSaving;

  /// No description provided for @roleSelectContinue.
  ///
  /// In bn, this message translates to:
  /// **'চালিয়ে যান'**
  String get roleSelectContinue;

  /// No description provided for @roleSelectSaveFailed.
  ///
  /// In bn, this message translates to:
  /// **'সংরক্ষণ ব্যর্থ: {error}'**
  String roleSelectSaveFailed(Object error);

  /// No description provided for @roleSelectRelationshipRequired.
  ///
  /// In bn, this message translates to:
  /// **'পরিচর্যাকারীর সম্পর্ক লিখুন (যেমন: ছেলে)।'**
  String get roleSelectRelationshipRequired;

  /// No description provided for @onboardingEditTitle.
  ///
  /// In bn, this message translates to:
  /// **'প্রোফাইল আপডেট'**
  String get onboardingEditTitle;

  /// No description provided for @onboardingNewTitle.
  ///
  /// In bn, this message translates to:
  /// **'নতুন প্রোফাইল'**
  String get onboardingNewTitle;

  /// No description provided for @onboardingStep1Title.
  ///
  /// In bn, this message translates to:
  /// **'মৌলিক তথ্য'**
  String get onboardingStep1Title;

  /// No description provided for @onboardingStep1Blurb.
  ///
  /// In bn, this message translates to:
  /// **'আপনার সম্পর্কে প্রাথমিক তথ্য'**
  String get onboardingStep1Blurb;

  /// No description provided for @onboardingStep2Title.
  ///
  /// In bn, this message translates to:
  /// **'গ্লুকোজ'**
  String get onboardingStep2Title;

  /// No description provided for @onboardingStep2Blurb.
  ///
  /// In bn, this message translates to:
  /// **'রক্তের গ্লুকোজ ও ওষুধ সম্পর্কে'**
  String get onboardingStep2Blurb;

  /// No description provided for @onboardingStep3Title.
  ///
  /// In bn, this message translates to:
  /// **'অবস্থা'**
  String get onboardingStep3Title;

  /// No description provided for @onboardingStep3Blurb.
  ///
  /// In bn, this message translates to:
  /// **'দীর্ঘস্থায়ী রোগ ও অবস্থা'**
  String get onboardingStep3Blurb;

  /// No description provided for @onboardingStep4Title.
  ///
  /// In bn, this message translates to:
  /// **'জীবনযাত্রা'**
  String get onboardingStep4Title;

  /// No description provided for @onboardingStep4Blurb.
  ///
  /// In bn, this message translates to:
  /// **'পরিশ্রম ও খাবারের অভ্যাস'**
  String get onboardingStep4Blurb;

  /// No description provided for @onboardingStep1Of4.
  ///
  /// In bn, this message translates to:
  /// **'ধাপ ১ / ৪'**
  String get onboardingStep1Of4;

  /// No description provided for @onboardingStep2Of4.
  ///
  /// In bn, this message translates to:
  /// **'ধাপ ২ / ৪'**
  String get onboardingStep2Of4;

  /// No description provided for @onboardingStep3Of4.
  ///
  /// In bn, this message translates to:
  /// **'ধাপ ৩ / ৪'**
  String get onboardingStep3Of4;

  /// No description provided for @onboardingStep4Of4.
  ///
  /// In bn, this message translates to:
  /// **'ধাপ ৪ / ৪'**
  String get onboardingStep4Of4;

  /// No description provided for @onboardingFieldFullName.
  ///
  /// In bn, this message translates to:
  /// **'পূর্ণ নাম'**
  String get onboardingFieldFullName;

  /// No description provided for @onboardingFieldFullNameHint.
  ///
  /// In bn, this message translates to:
  /// **'নাম লিখুন'**
  String get onboardingFieldFullNameHint;

  /// No description provided for @onboardingOptional.
  ///
  /// In bn, this message translates to:
  /// **'ঐচ্ছিক'**
  String get onboardingOptional;

  /// No description provided for @onboardingRequired6.
  ///
  /// In bn, this message translates to:
  /// **'আবশ্যক • ৬ অক্ষর'**
  String get onboardingRequired6;

  /// No description provided for @onboardingMobile.
  ///
  /// In bn, this message translates to:
  /// **'মোবাইল নম্বর'**
  String get onboardingMobile;

  /// No description provided for @onboardingUsername.
  ///
  /// In bn, this message translates to:
  /// **'ইউজারনেম'**
  String get onboardingUsername;

  /// No description provided for @onboardingAge.
  ///
  /// In bn, this message translates to:
  /// **'বয়স'**
  String get onboardingAge;

  /// No description provided for @onboardingWeight.
  ///
  /// In bn, this message translates to:
  /// **'ওজন (কেজি)'**
  String get onboardingWeight;

  /// No description provided for @onboardingHeight.
  ///
  /// In bn, this message translates to:
  /// **'উচ্চতা (সেমি)'**
  String get onboardingHeight;

  /// No description provided for @onboardingSex.
  ///
  /// In bn, this message translates to:
  /// **'লিঙ্গ'**
  String get onboardingSex;

  /// No description provided for @onboardingSexMale.
  ///
  /// In bn, this message translates to:
  /// **'পুরুষ'**
  String get onboardingSexMale;

  /// No description provided for @onboardingSexFemale.
  ///
  /// In bn, this message translates to:
  /// **'মহিলা'**
  String get onboardingSexFemale;

  /// No description provided for @onboardingSexOther.
  ///
  /// In bn, this message translates to:
  /// **'অন্যান্য'**
  String get onboardingSexOther;

  /// No description provided for @onboardingFastingGlucose.
  ///
  /// In bn, this message translates to:
  /// **'ফাস্টিং গ্লুকোজ'**
  String get onboardingFastingGlucose;

  /// No description provided for @onboardingPostMealGlucose.
  ///
  /// In bn, this message translates to:
  /// **'খাবার-পর গ্লুকোজ'**
  String get onboardingPostMealGlucose;

  /// No description provided for @onboardingHba1c.
  ///
  /// In bn, this message translates to:
  /// **'HbA1c'**
  String get onboardingHba1c;

  /// No description provided for @onboardingMedicationLabel.
  ///
  /// In bn, this message translates to:
  /// **'ওষুধ / ইনসুলিন'**
  String get onboardingMedicationLabel;

  /// No description provided for @onboardingOnInsulin.
  ///
  /// In bn, this message translates to:
  /// **'ইনসুলিন গ্রহণ করছি'**
  String get onboardingOnInsulin;

  /// No description provided for @onboardingMedicationHint.
  ///
  /// In bn, this message translates to:
  /// **'ওষুধের নাম লিখুন (ঐচ্ছিক)'**
  String get onboardingMedicationHint;

  /// No description provided for @onboardingBp.
  ///
  /// In bn, this message translates to:
  /// **'রক্তচাপ (mmHg)'**
  String get onboardingBp;

  /// No description provided for @onboardingSystolic.
  ///
  /// In bn, this message translates to:
  /// **'সিস্টোলিক'**
  String get onboardingSystolic;

  /// No description provided for @onboardingDiastolic.
  ///
  /// In bn, this message translates to:
  /// **'ডায়াস্টোলিক'**
  String get onboardingDiastolic;

  /// No description provided for @onboardingChronic.
  ///
  /// In bn, this message translates to:
  /// **'দীর্ঘস্থায়ী অবস্থা'**
  String get onboardingChronic;

  /// No description provided for @onboardingCkdLabel.
  ///
  /// In bn, this message translates to:
  /// **'কিডনি রোগ (CKD)'**
  String get onboardingCkdLabel;

  /// No description provided for @onboardingCkdSub.
  ///
  /// In bn, this message translates to:
  /// **'কিডনি সংক্রান্ত খাবার সীমিত হবে'**
  String get onboardingCkdSub;

  /// No description provided for @onboardingHeartLabel.
  ///
  /// In bn, this message translates to:
  /// **'হৃদরোগ'**
  String get onboardingHeartLabel;

  /// No description provided for @onboardingHeartSub.
  ///
  /// In bn, this message translates to:
  /// **'কম সোডিয়াম ও কম চর্বির পরামর্শ'**
  String get onboardingHeartSub;

  /// No description provided for @onboardingAnemiaLabel.
  ///
  /// In bn, this message translates to:
  /// **'রক্তস্বল্পতা'**
  String get onboardingAnemiaLabel;

  /// No description provided for @onboardingAnemiaSub.
  ///
  /// In bn, this message translates to:
  /// **'আয়রন-সমৃদ্ধ খাবার বেশি দেখানো হবে'**
  String get onboardingAnemiaSub;

  /// No description provided for @onboardingOtherConditions.
  ///
  /// In bn, this message translates to:
  /// **'অন্যান্য অবস্থা'**
  String get onboardingOtherConditions;

  /// No description provided for @onboardingOtherConditionsHint.
  ///
  /// In bn, this message translates to:
  /// **'যেমন: থাইরয়েড, গর্ভাবস্থা…'**
  String get onboardingOtherConditionsHint;

  /// No description provided for @onboardingActivity.
  ///
  /// In bn, this message translates to:
  /// **'শারীরিক পরিশ্রম'**
  String get onboardingActivity;

  /// No description provided for @onboardingActivityLow.
  ///
  /// In bn, this message translates to:
  /// **'কম'**
  String get onboardingActivityLow;

  /// No description provided for @onboardingActivityModerate.
  ///
  /// In bn, this message translates to:
  /// **'মাঝারি'**
  String get onboardingActivityModerate;

  /// No description provided for @onboardingActivityHigh.
  ///
  /// In bn, this message translates to:
  /// **'বেশি'**
  String get onboardingActivityHigh;

  /// No description provided for @onboardingMealSize.
  ///
  /// In bn, this message translates to:
  /// **'খাবারের পরিমাণ'**
  String get onboardingMealSize;

  /// No description provided for @onboardingMealSizeSmall.
  ///
  /// In bn, this message translates to:
  /// **'অল্প'**
  String get onboardingMealSizeSmall;

  /// No description provided for @onboardingMealSizeMedium.
  ///
  /// In bn, this message translates to:
  /// **'মাঝারি'**
  String get onboardingMealSizeMedium;

  /// No description provided for @onboardingMealSizeLarge.
  ///
  /// In bn, this message translates to:
  /// **'বেশি'**
  String get onboardingMealSizeLarge;

  /// No description provided for @onboardingFoodPref.
  ///
  /// In bn, this message translates to:
  /// **'খাবারের ধরন'**
  String get onboardingFoodPref;

  /// No description provided for @onboardingFoodPrefOmnivore.
  ///
  /// In bn, this message translates to:
  /// **'সর্বভুক'**
  String get onboardingFoodPrefOmnivore;

  /// No description provided for @onboardingFoodPrefVegetarian.
  ///
  /// In bn, this message translates to:
  /// **'নিরামিষ'**
  String get onboardingFoodPrefVegetarian;

  /// No description provided for @onboardingFoodPrefFishOnly.
  ///
  /// In bn, this message translates to:
  /// **'শুধু মাছ'**
  String get onboardingFoodPrefFishOnly;

  /// No description provided for @onboardingFoodPrefNoBeef.
  ///
  /// In bn, this message translates to:
  /// **'গরু ছাড়া'**
  String get onboardingFoodPrefNoBeef;

  /// No description provided for @onboardingDisclaimer.
  ///
  /// In bn, this message translates to:
  /// **'এই তথ্য শুধু পরামর্শের জন্য। যেকোনো পরিবর্তনের আগে আপনার চিকিৎসকের সাথে কথা বলুন।'**
  String get onboardingDisclaimer;

  /// No description provided for @onboardingPrevious.
  ///
  /// In bn, this message translates to:
  /// **'পূর্বে'**
  String get onboardingPrevious;

  /// No description provided for @onboardingNext.
  ///
  /// In bn, this message translates to:
  /// **'পরবর্তী'**
  String get onboardingNext;

  /// No description provided for @onboardingFinish.
  ///
  /// In bn, this message translates to:
  /// **'পরিকল্পনা তৈরি করুন'**
  String get onboardingFinish;

  /// No description provided for @onboardingFieldRequired.
  ///
  /// In bn, this message translates to:
  /// **'আবশ্যক'**
  String get onboardingFieldRequired;

  /// No description provided for @onboardingFieldNumber.
  ///
  /// In bn, this message translates to:
  /// **'সংখ্যা দিন'**
  String get onboardingFieldNumber;

  /// No description provided for @onboardingUsernameFormat.
  ///
  /// In bn, this message translates to:
  /// **'৬ অক্ষরের ইউজারনেম দিন'**
  String get onboardingUsernameFormat;

  /// No description provided for @onboardingUsernameCharset.
  ///
  /// In bn, this message translates to:
  /// **'ইংরেজি অক্ষর, সংখ্যা ও আন্ডারস্কোর ব্যবহার করুন'**
  String get onboardingUsernameCharset;

  /// No description provided for @onboardingAgeRange.
  ///
  /// In bn, this message translates to:
  /// **'বয়স ১ থেকে ১২০ এর মধ্যে হতে হবে'**
  String get onboardingAgeRange;

  /// No description provided for @onboardingWeightInvalid.
  ///
  /// In bn, this message translates to:
  /// **'ওজন সঠিক নয়'**
  String get onboardingWeightInvalid;

  /// No description provided for @onboardingHeightInvalid.
  ///
  /// In bn, this message translates to:
  /// **'উচ্চতা সঠিক নয়'**
  String get onboardingHeightInvalid;

  /// No description provided for @onboardingSaveFailed.
  ///
  /// In bn, this message translates to:
  /// **'সংরক্ষণ ব্যর্থ: {error}'**
  String onboardingSaveFailed(Object error);

  /// No description provided for @onboardingErrNoInternet.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট সংযোগ নেই'**
  String get onboardingErrNoInternet;

  /// No description provided for @onboardingErrNoPermission.
  ///
  /// In bn, this message translates to:
  /// **'অনুমতি নেই — সেশন রিফ্রেশ করুন'**
  String get onboardingErrNoPermission;

  /// No description provided for @onboardingErrOutOfRange.
  ///
  /// In bn, this message translates to:
  /// **'তথ্য সীমার বাইরে'**
  String get onboardingErrOutOfRange;

  /// No description provided for @onboardingErrUsernameTaken.
  ///
  /// In bn, this message translates to:
  /// **'এই ইউজারনেমটি ইতিমধ্যে নেওয়া হয়েছে — অন্যটি বেছে নিন'**
  String get onboardingErrUsernameTaken;

  /// No description provided for @onboardingErrRetry.
  ///
  /// In bn, this message translates to:
  /// **'আবার চেষ্টা করুন'**
  String get onboardingErrRetry;

  /// No description provided for @onboardingWarningsTitle.
  ///
  /// In bn, this message translates to:
  /// **'গুরুত্বপূর্ণ'**
  String get onboardingWarningsTitle;

  /// No description provided for @onboardingGotIt.
  ///
  /// In bn, this message translates to:
  /// **'বুঝেছি'**
  String get onboardingGotIt;

  /// No description provided for @authLoginTitle.
  ///
  /// In bn, this message translates to:
  /// **'লগইন করুন'**
  String get authLoginTitle;

  /// No description provided for @authSignupTitle.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাকাউন্ট তৈরি করুন'**
  String get authSignupTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In bn, this message translates to:
  /// **'আপনার অ্যাকাউন্টে প্রবেশ করুন।'**
  String get authLoginSubtitle;

  /// No description provided for @authSignupSubtitle.
  ///
  /// In bn, this message translates to:
  /// **'ব্যক্তিগতকৃত পরিকল্পনা পেতে কয়েকটি তথ্য দিন।'**
  String get authSignupSubtitle;

  /// No description provided for @authOverlineLogin.
  ///
  /// In bn, this message translates to:
  /// **'স্বাগতম ফিরে'**
  String get authOverlineLogin;

  /// No description provided for @authOverlineSignup.
  ///
  /// In bn, this message translates to:
  /// **'নতুন অ্যাকাউন্ট'**
  String get authOverlineSignup;

  /// No description provided for @authLogin.
  ///
  /// In bn, this message translates to:
  /// **'লগইন'**
  String get authLogin;

  /// No description provided for @authSignup.
  ///
  /// In bn, this message translates to:
  /// **'সাইন আপ'**
  String get authSignup;

  /// No description provided for @authFullName.
  ///
  /// In bn, this message translates to:
  /// **'আপনার নাম'**
  String get authFullName;

  /// No description provided for @authFullNameHint.
  ///
  /// In bn, this message translates to:
  /// **'যেমন: রহিম মিয়া'**
  String get authFullNameHint;

  /// No description provided for @authMobile.
  ///
  /// In bn, this message translates to:
  /// **'মোবাইল নম্বর'**
  String get authMobile;

  /// No description provided for @authMobileHint.
  ///
  /// In bn, this message translates to:
  /// **'01XXXXXXXXX'**
  String get authMobileHint;

  /// No description provided for @authUsername.
  ///
  /// In bn, this message translates to:
  /// **'ইউজারনেম'**
  String get authUsername;

  /// No description provided for @authUsernameHint.
  ///
  /// In bn, this message translates to:
  /// **'6 অক্ষর (যেমন: nazmul)'**
  String get authUsernameHint;

  /// No description provided for @authRoleQuestion.
  ///
  /// In bn, this message translates to:
  /// **'আপনি কি রোগী নাকি পরিচর্যাকারী?'**
  String get authRoleQuestion;

  /// No description provided for @authRolePatient.
  ///
  /// In bn, this message translates to:
  /// **'রোগী'**
  String get authRolePatient;

  /// No description provided for @authRoleCaregiver.
  ///
  /// In bn, this message translates to:
  /// **'পরিচর্যাকারী'**
  String get authRoleCaregiver;

  /// No description provided for @authRelationship.
  ///
  /// In bn, this message translates to:
  /// **'আপনার সম্পর্ক'**
  String get authRelationship;

  /// No description provided for @authRelationshipHint.
  ///
  /// In bn, this message translates to:
  /// **'যেমন: ছেলে, স্বামী, পরিচর্যাকারী'**
  String get authRelationshipHint;

  /// No description provided for @authEmail.
  ///
  /// In bn, this message translates to:
  /// **'ইমেইল'**
  String get authEmail;

  /// No description provided for @authEmailHint.
  ///
  /// In bn, this message translates to:
  /// **'example@mail.com'**
  String get authEmailHint;

  /// No description provided for @authPassword.
  ///
  /// In bn, this message translates to:
  /// **'পাসওয়ার্ড'**
  String get authPassword;

  /// No description provided for @authPasswordHint.
  ///
  /// In bn, this message translates to:
  /// **'কমপক্ষে ৬ অক্ষর'**
  String get authPasswordHint;

  /// No description provided for @authForgotPassword.
  ///
  /// In bn, this message translates to:
  /// **'পাসওয়ার্ড ভুলে গেছেন?'**
  String get authForgotPassword;

  /// No description provided for @authShowPassword.
  ///
  /// In bn, this message translates to:
  /// **'দেখান'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In bn, this message translates to:
  /// **'লুকান'**
  String get authHidePassword;

  /// No description provided for @authToggleToSignup.
  ///
  /// In bn, this message translates to:
  /// **'প্রথমবার?  নতুন অ্যাকাউন্ট তৈরি করুন →'**
  String get authToggleToSignup;

  /// No description provided for @authToggleToLogin.
  ///
  /// In bn, this message translates to:
  /// **'ইতোমধ্যে অ্যাকাউন্ট আছে?  লগইন →'**
  String get authToggleToLogin;

  /// No description provided for @authBrand.
  ///
  /// In bn, this message translates to:
  /// **'আপন সুস্থতা'**
  String get authBrand;

  /// No description provided for @authHeroTitle.
  ///
  /// In bn, this message translates to:
  /// **'ডায়াবেটিস-সহায়ক\nখাবারের পথে\nআপনার সঙ্গী'**
  String get authHeroTitle;

  /// No description provided for @authHeroTitleCompact.
  ///
  /// In bn, this message translates to:
  /// **'ডায়াবেটিস-সহায়ক\nখাবারের পথে'**
  String get authHeroTitleCompact;

  /// No description provided for @authHeroSub.
  ///
  /// In bn, this message translates to:
  /// **'ব্যক্তিগতকৃত খাবারের পরিকল্পনা, দৈনিক লগ, এবং স্বাস্থ্য-সম্মত সুপারিশ — সব এক জায়গায়।'**
  String get authHeroSub;

  /// No description provided for @authHeroSubCompact.
  ///
  /// In bn, this message translates to:
  /// **'ব্যক্তিগতকৃত পরিকল্পনা, সহজ ট্র্যাকিং।'**
  String get authHeroSubCompact;

  /// No description provided for @authHeroBulletLocal.
  ///
  /// In bn, this message translates to:
  /// **'বাংলাদেশী খাবার'**
  String get authHeroBulletLocal;

  /// No description provided for @authHeroBulletSenior.
  ///
  /// In bn, this message translates to:
  /// **'বয়স্ক-বান্ধব'**
  String get authHeroBulletSenior;

  /// No description provided for @authHeroBulletFree.
  ///
  /// In bn, this message translates to:
  /// **'ফ্রি'**
  String get authHeroBulletFree;

  /// No description provided for @authConnChecking.
  ///
  /// In bn, this message translates to:
  /// **'সংযোগ পরীক্ষা হচ্ছে…'**
  String get authConnChecking;

  /// No description provided for @authConnOnline.
  ///
  /// In bn, this message translates to:
  /// **'সার্ভারে সংযুক্ত'**
  String get authConnOnline;

  /// No description provided for @authConnOffline.
  ///
  /// In bn, this message translates to:
  /// **'সংযোগ ব্যর্থ — আবার চেষ্টা করুন'**
  String get authConnOffline;

  /// No description provided for @authErrEmailPassword.
  ///
  /// In bn, this message translates to:
  /// **'ইমেইল ও পাসওয়ার্ড দিন'**
  String get authErrEmailPassword;

  /// No description provided for @authErrFullName.
  ///
  /// In bn, this message translates to:
  /// **'আপনার নাম লিখুন'**
  String get authErrFullName;

  /// No description provided for @authErrMobile.
  ///
  /// In bn, this message translates to:
  /// **'মোবাইল নম্বর সঠিকভাবে দিন'**
  String get authErrMobile;

  /// No description provided for @authErrRelationship.
  ///
  /// In bn, this message translates to:
  /// **'পরিচর্যাকারীর সম্পর্ক লিখুন (যেমন: ছেলে)।'**
  String get authErrRelationship;

  /// No description provided for @authErrResetEmail.
  ///
  /// In bn, this message translates to:
  /// **'রিসেট লিংক পাঠাতে ইমেইল দিন'**
  String get authErrResetEmail;

  /// No description provided for @authErrResetSent.
  ///
  /// In bn, this message translates to:
  /// **'✅ রিসেট লিংক পাঠানো হয়েছে — {email} ইমেইল দেখুন'**
  String authErrResetSent(Object email);

  /// No description provided for @authErrResetFailed.
  ///
  /// In bn, this message translates to:
  /// **'রিসেট ব্যর্থ: {error}'**
  String authErrResetFailed(Object error);

  /// No description provided for @authErrLoginPrefix.
  ///
  /// In bn, this message translates to:
  /// **'লগইন ব্যর্থ: {error}'**
  String authErrLoginPrefix(Object error);

  /// No description provided for @authErrSignupPrefix.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাকাউন্ট তৈরি ব্যর্থ: {error}'**
  String authErrSignupPrefix(Object error);

  /// No description provided for @workoutHeroSectionTitle.
  ///
  /// In bn, this message translates to:
  /// **'আজকের ব্যায়াম'**
  String get workoutHeroSectionTitle;

  /// No description provided for @workoutProgressTitle.
  ///
  /// In bn, this message translates to:
  /// **'আজকের অগ্রগতি'**
  String get workoutProgressTitle;

  /// No description provided for @workoutProgressPctLabel.
  ///
  /// In bn, this message translates to:
  /// **'সামগ্রিক অগ্রগতি'**
  String get workoutProgressPctLabel;

  /// No description provided for @workoutStatusDone.
  ///
  /// In bn, this message translates to:
  /// **'সম্পন্ন'**
  String get workoutStatusDone;

  /// No description provided for @workoutStatusPartial.
  ///
  /// In bn, this message translates to:
  /// **'আংশিক'**
  String get workoutStatusPartial;

  /// No description provided for @workoutStatusPending.
  ///
  /// In bn, this message translates to:
  /// **'শুরু হয়নি'**
  String get workoutStatusPending;

  /// No description provided for @workoutProgressPartialSuffix.
  ///
  /// In bn, this message translates to:
  /// **'কাছাকাছি আছেন'**
  String get workoutProgressPartialSuffix;

  /// No description provided for @workoutProgressFullSuffix.
  ///
  /// In bn, this message translates to:
  /// **'চাহিদা পূরণ হয়েছে'**
  String get workoutProgressFullSuffix;

  /// No description provided for @workoutAggregateDoneLabel.
  ///
  /// In bn, this message translates to:
  /// **'সম্পন্ন হয়েছে'**
  String get workoutAggregateDoneLabel;

  /// No description provided for @workoutAggregatePartialLabel.
  ///
  /// In bn, this message translates to:
  /// **'আংশিক সম্পন্ন'**
  String get workoutAggregatePartialLabel;

  /// No description provided for @workoutAggregatePendingLabel.
  ///
  /// In bn, this message translates to:
  /// **'বাকি আছে'**
  String get workoutAggregatePendingLabel;

  /// No description provided for @workoutAggregateOfLabel.
  ///
  /// In bn, this message translates to:
  /// **'আজকের মোট'**
  String get workoutAggregateOfLabel;

  /// Status line: {actual} min done out of {total} total today. {pct}% overall.
  ///
  /// In bn, this message translates to:
  /// **'করেছেন {actual} / {total} মিনিট · {pct}% সামগ্রিক'**
  String workoutProgressOfTotal(int actual, int total, int pct);

  /// Hint shown below a partially-done workout.
  ///
  /// In bn, this message translates to:
  /// **'আরও {remaining} মিনিট বাকি আছে'**
  String workoutProgressHintPartial(int remaining);

  /// No description provided for @workoutProgressHintDone.
  ///
  /// In bn, this message translates to:
  /// **'আজকের লক্ষ্য পূরণ হয়েছে'**
  String get workoutProgressHintDone;

  /// No description provided for @workoutProgressHintPending.
  ///
  /// In bn, this message translates to:
  /// **'এখনো শুরু হয়নি'**
  String get workoutProgressHintPending;

  /// No description provided for @mealProgressTitle.
  ///
  /// In bn, this message translates to:
  /// **'আজকের খাবারের অগ্রগতি'**
  String get mealProgressTitle;

  /// No description provided for @mealProgressPctLabel.
  ///
  /// In bn, this message translates to:
  /// **'সামগ্রিক অগ্রগতি'**
  String get mealProgressPctLabel;

  /// No description provided for @mealStatusEaten.
  ///
  /// In bn, this message translates to:
  /// **'খাওয়া হয়েছে'**
  String get mealStatusEaten;

  /// No description provided for @mealStatusPending.
  ///
  /// In bn, this message translates to:
  /// **'বাকি আছে'**
  String get mealStatusPending;

  /// No description provided for @mealAggregateEatenLabel.
  ///
  /// In bn, this message translates to:
  /// **'খাওয়া হয়েছে'**
  String get mealAggregateEatenLabel;

  /// No description provided for @mealAggregatePendingLabel.
  ///
  /// In bn, this message translates to:
  /// **'বাকি আছে'**
  String get mealAggregatePendingLabel;

  /// Status line: {eaten} items eaten out of {total} total today. {pct}% overall.
  ///
  /// In bn, this message translates to:
  /// **'খেয়েছেন {eaten} / {total}টি খাবার · {pct}% সামগ্রিক'**
  String mealProgressOfTotal(int eaten, int total, int pct);

  /// No description provided for @sosTitle.
  ///
  /// In bn, this message translates to:
  /// **'জরুরি যোগাযোগ'**
  String get sosTitle;

  /// No description provided for @sosNearestCta.
  ///
  /// In bn, this message translates to:
  /// **'আমার কাছের হাসপাতাল'**
  String get sosNearestCta;

  /// No description provided for @sosHotlinesTitle.
  ///
  /// In bn, this message translates to:
  /// **'জাতীয় হেল্পলাইন'**
  String get sosHotlinesTitle;

  /// No description provided for @sosPickDivision.
  ///
  /// In bn, this message translates to:
  /// **'বিভাগ'**
  String get sosPickDivision;

  /// No description provided for @sosPickDistrict.
  ///
  /// In bn, this message translates to:
  /// **'জেলা'**
  String get sosPickDistrict;

  /// No description provided for @sosPickUpazila.
  ///
  /// In bn, this message translates to:
  /// **'উপজেলা'**
  String get sosPickUpazila;

  /// No description provided for @sosCall.
  ///
  /// In bn, this message translates to:
  /// **'কল'**
  String get sosCall;

  /// No description provided for @sosCopy.
  ///
  /// In bn, this message translates to:
  /// **'কপি'**
  String get sosCopy;

  /// No description provided for @sosCopied.
  ///
  /// In bn, this message translates to:
  /// **'নম্বর কপি হয়েছে'**
  String get sosCopied;

  /// No description provided for @sosNoPermission.
  ///
  /// In bn, this message translates to:
  /// **'লোকেশন অনুমতি দরকার'**
  String get sosNoPermission;

  /// No description provided for @sosNoGps.
  ///
  /// In bn, this message translates to:
  /// **'GPS পাওয়া যায়নি'**
  String get sosNoGps;

  /// No description provided for @sosNearbyEmpty.
  ///
  /// In bn, this message translates to:
  /// **'কাছে কোনো হাসপাতাল পাওয়া যায়নি'**
  String get sosNearbyEmpty;

  /// No description provided for @sosPickAny.
  ///
  /// In bn, this message translates to:
  /// **'যেকোনো একটি বেছে নিন'**
  String get sosPickAny;

  /// No description provided for @sosHospitalsInDistrict.
  ///
  /// In bn, this message translates to:
  /// **'এই জেলার হাসপাতাল'**
  String get sosHospitalsInDistrict;

  /// No description provided for @sosAllHospitals.
  ///
  /// In bn, this message translates to:
  /// **'সব হাসপাতাল'**
  String get sosAllHospitals;

  /// Distance label in kilometers.
  ///
  /// In bn, this message translates to:
  /// **'{km} কিমি'**
  String sosDistanceKm(String km);
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
