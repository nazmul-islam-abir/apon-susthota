// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Apon Susthota';

  @override
  String get helloGreeting => 'Hello,';

  @override
  String get friendName => 'Friend';

  @override
  String get yourLocation => 'Your location';

  @override
  String get languageBn => 'বাংলা (Bangla)';

  @override
  String get languageEn => 'English';

  @override
  String get searchHint => 'Search services...';

  @override
  String get heroHeadline => 'Your wellness,\nin one tap!';

  @override
  String get heroSubhead =>
      'Simple, fast, reliable\neverything at your fingertips';

  @override
  String get exploreCta => 'Explore';

  @override
  String get sectionCategories => 'Service Categories';

  @override
  String get sectionCategoriesSub => 'All the services you need';

  @override
  String get sectionPopular => 'Popular Services';

  @override
  String get sectionPopularSub => 'Commonly used services';

  @override
  String get sectionHealth => 'Health Status';

  @override
  String get sectionHealthSub => 'Your current vitals';

  @override
  String get seeAll => 'See all';

  @override
  String get serviceWater => 'Water';

  @override
  String get serviceWaterSub => 'Water tracker';

  @override
  String get serviceCare => 'Care';

  @override
  String get serviceCareSub => 'Connected people';

  @override
  String get serviceFood => 'Food';

  @override
  String get serviceFoodSub => 'Meal planner';

  @override
  String get serviceWorkout => 'Workout';

  @override
  String get serviceWorkoutSub => 'Workout routines';

  @override
  String get popularMeal => 'Meal Logging';

  @override
  String get popularMealSub => 'Daily meal list';

  @override
  String get popularWorkout => 'Workout Plan';

  @override
  String get popularWorkoutSub => 'Your physical routine';

  @override
  String get popularMedicine => 'Medicine Reminder';

  @override
  String get popularMedicineSub => 'Take meds on time';

  @override
  String get popularAnalytics => 'Health Analytics';

  @override
  String get popularAnalyticsSub => 'Your progress report';

  @override
  String get popularWater => 'Water Tracker';

  @override
  String get popularWaterSub => 'Stay hydrated';

  @override
  String get popularProfile => 'Profile Info';

  @override
  String get popularProfileSub => 'Your personal settings';

  @override
  String get priceFree => 'Free';

  @override
  String get reviewsLabel => 'reviews';

  @override
  String get loadFailed => 'Could not load data';

  @override
  String get retry => 'Retry';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navMeal => 'Today';

  @override
  String get navWorkout => 'Workout';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navAi => 'AI Assistant';

  @override
  String get moodBannerTitle => 'Today\'s mood';

  @override
  String get moodBannerSubtitle => 'Hold 2 sec to record';

  @override
  String get moodLoggedPrefix => 'Today you logged:';

  @override
  String get moodEditTooltip => 'Edit mood';

  @override
  String get moodSheetTitle => 'Daily health check-in';

  @override
  String get sleepHoursLabel => 'Sleep hours';

  @override
  String get energyLevelLabel => 'Energy level';

  @override
  String get stressLevelLabel => 'Stress level';

  @override
  String get symptomsLabel => 'Symptoms (optional)';

  @override
  String get symptomsHint => 'Any physical issues today?';

  @override
  String get moodSavedToast => 'Today\'s mood saved';

  @override
  String get moodSavingToast => 'Saving...';

  @override
  String get moodReminderPrompt =>
      'End your day with care — how are you feeling?';

  @override
  String get moodReminderClose => 'Later';

  @override
  String get moodSaveButton => 'Save';

  @override
  String get exitMessage => 'Leave the app?';

  @override
  String get exitTitle => 'Close the app?';

  @override
  String get exitConfirm => 'Exit';

  @override
  String get exitCancel => 'Stay';

  @override
  String get backTooltip => 'Go back';

  @override
  String get pendingActionIntro => 'I want to:';

  @override
  String get pendingActionConfirm => 'Confirm';

  @override
  String get pendingActionCancel => 'Cancel';

  @override
  String get pendingActionDetails => 'Show details';

  @override
  String get pendingActionCollapse => 'Hide details';

  @override
  String get pendingActionFallbackError =>
      'Something went wrong — please try again.';

  @override
  String get toolUndone => 'Undone';

  @override
  String get toolCancelled => 'Cancelled';

  @override
  String toolUndoButton(Object seconds) {
    return 'Undo ($seconds)';
  }

  @override
  String get toolUndoExpired => 'Undo window has closed.';

  @override
  String get restrictedFoodsTitle => 'Foods to avoid';

  @override
  String get restrictedFoodsBlurb =>
      'Based on your current health condition, limit or avoid the foods below.';

  @override
  String restrictedFoodsMore(Object count) {
    return '$count more items — edit your profile to see all.';
  }

  @override
  String get restrictedFoodsEmpty =>
      'Based on your current health data, there are no specific restricted foods. Continue as advised by your doctor.';

  @override
  String get classificationTitle => 'Your current classification';

  @override
  String get classificationGlucose => 'Glucose';

  @override
  String get classificationBmi => 'BMI';

  @override
  String get classificationBp => 'Blood pressure';

  @override
  String get classificationDailyTargets => 'Daily targets';

  @override
  String get classificationKcal => 'Calories';

  @override
  String get classificationCarb => 'Carbs';

  @override
  String get classificationProtein => 'Protein';

  @override
  String get classificationFat => 'Fat';

  @override
  String get classificationSodium => 'Sodium max';

  @override
  String get classificationCarbPerMeal => 'Carbs per meal';

  @override
  String classificationValueKcal(Object value) {
    return '$value kcal';
  }

  @override
  String classificationValueG(Object value) {
    return '$value g';
  }

  @override
  String classificationValueMg(Object value) {
    return '$value mg';
  }

  @override
  String get tierGood => 'Good';

  @override
  String get tierModerate => 'Moderate';

  @override
  String get tierPoor => 'Poor';

  @override
  String get tierUnderweight => 'Underweight';

  @override
  String get tierNormal => 'Normal';

  @override
  String get tierOverweight => 'Overweight';

  @override
  String get tierObese => 'Obese';

  @override
  String get tierElevated => 'Elevated';

  @override
  String get tierStage1 => 'Stage 1';

  @override
  String get tierStage2 => 'Stage 2';

  @override
  String get tierUnknown => 'Unknown';

  @override
  String get recommendationsTitle => 'Personal advice';

  @override
  String get clinicalSnapshotTitle => 'Current health status';

  @override
  String get clinicalSnapshotWarnings => 'Warnings';

  @override
  String get clinicalSnapshotFood => 'Food';

  @override
  String get macroCarb => 'Carbs';

  @override
  String macroCarbValue(Object value) {
    return '$value g';
  }

  @override
  String get macroKcal => 'Calories';

  @override
  String get macroSodium => 'Sodium';

  @override
  String macroSodiumValue(Object value) {
    return '$value mg';
  }

  @override
  String get foodPrefOmnivore => 'All foods';

  @override
  String get foodPrefVegetarian => 'Vegetarian';

  @override
  String get foodPrefFishOnly => 'Fish only';

  @override
  String get foodPrefNoBeef => 'No beef';

  @override
  String get caretakerNavPatients => 'Patients';

  @override
  String get caretakerNavHome => 'Home';

  @override
  String get caretakerNavToday => 'Today';

  @override
  String get caretakerNavInbox => 'Inbox';

  @override
  String get caretakerNavSearch => 'Search';

  @override
  String get rolePatient => 'Patient';

  @override
  String get roleCaregiver => 'Caregiver';

  @override
  String get rolePatientCaption => 'Personal mode';

  @override
  String get roleCaregiverCaption => 'View mode';

  @override
  String roleChipSemantics(Object role) {
    return 'Current role: $role';
  }

  @override
  String get drawerProfile => 'Profile';

  @override
  String get drawerProfileSub => 'My info & settings';

  @override
  String get drawerMedicine => 'Medicine';

  @override
  String get drawerMedicineSub => 'Medicine reminders & tracker';

  @override
  String get drawerWater => 'Water';

  @override
  String get drawerWaterSub => 'Daily goals & tracker';

  @override
  String get drawerDoctorReport => 'Doctor\'s report';

  @override
  String get drawerDoctorReportSub => '30-day cycle & PDF';

  @override
  String get drawerMyCaretakers => 'My caretakers';

  @override
  String get drawerMyCaretakersSub => 'Who is monitoring you';

  @override
  String get drawerLogout => 'Log out';

  @override
  String get drawerLogoutSub => 'Sign out of your account';

  @override
  String get drawerViewProfile => 'View my profile →';

  @override
  String get drawerFriend => 'Friend';

  @override
  String get drawerInitial => 'A';

  @override
  String drawerAppVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get videoLabelGuide => 'Video guide';

  @override
  String get videoUnavailable => 'Cannot load video';

  @override
  String get videoComingSoonTitle => 'Video coming soon';

  @override
  String get videoComingSoonSub => 'Read the workout details first';

  @override
  String get videoNoneTitle => 'No video';

  @override
  String get videoNoneSub => 'This workout has no video yet';

  @override
  String get videoTapToPlay => 'Tap to play';

  @override
  String get videoMuted => 'Muted';

  @override
  String get videoSoundOn => 'Sound on';

  @override
  String get videoPlay => 'Play';

  @override
  String get videoPause => 'Pause';

  @override
  String get videoSkip => 'Skip';

  @override
  String get videoUrlMissing => 'Video URL not found';

  @override
  String get videoPlaybackError =>
      'Cannot play video — storage file or signed URL may be the issue';

  @override
  String get splashBrandBn => 'Apon Susthota';

  @override
  String get setupErrorOverline => 'Setup issue';

  @override
  String get setupErrorHeadline => 'Supabase connection failed';

  @override
  String get setupErrorUnknown => 'Unknown setup error — check the logs.';

  @override
  String get setupErrorStepsTitle => 'What to do';

  @override
  String get setupErrorStep1Title => 'Create a .env file';

  @override
  String get setupErrorStep1Body =>
      'Copy .env.example at the project root and save it as .env.';

  @override
  String get setupErrorStep2Title => 'Add Supabase keys';

  @override
  String get setupErrorStep2Body =>
      'Fill in SUPABASE_URL and SUPABASE_ANON_KEY (Supabase Dashboard → Project Settings → API).';

  @override
  String get setupErrorStep3Title => 'Restart the app';

  @override
  String get setupErrorStep3Body =>
      'Run flutter run again — the setup screen will no longer appear.';

  @override
  String get setupErrorCopyButton => 'Copy: SUPABASE_URL needed';

  @override
  String get setupErrorCopied => 'Copied to clipboard.';

  @override
  String get roleSelectTitle => 'Who are you?';

  @override
  String get roleSelectHeadline => 'Choose your account type';

  @override
  String get roleSelectBlurb =>
      'Are you a diabetes patient, or a family member caring for someone?';

  @override
  String get roleCardPatientTitle => 'Patient';

  @override
  String get roleCardPatientEn => 'Patient';

  @override
  String get roleCardPatientDesc =>
      'I manage my own diabetes. I\'ll see my own food, medicine and workout plans.';

  @override
  String get roleCardCaregiverTitle => 'Caregiver';

  @override
  String get roleCardCaregiverEn => 'Caregiver';

  @override
  String get roleCardCaregiverDesc =>
      'I care for someone else (father/mother/husband/wife). I\'ll watch over their food and medicine — but won\'t edit any analytics or plans.';

  @override
  String get roleSelectRelationshipOverline => 'Your relationship';

  @override
  String get roleSelectRelationshipHint =>
      'e.g.: son, daughter, husband, wife, caregiver';

  @override
  String get roleSelectClinicalNote =>
      'Clinical policy: caregivers may never edit a patient\'s analytics, meal plan or profile — they can only view, and log food/medicine when needed.';

  @override
  String get roleSelectSaving => 'Saving…';

  @override
  String get roleSelectContinue => 'Continue';

  @override
  String roleSelectSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get roleSelectRelationshipRequired =>
      'Please enter the caregiver\'s relationship (e.g.: son).';

  @override
  String get onboardingEditTitle => 'Update profile';

  @override
  String get onboardingNewTitle => 'New profile';

  @override
  String get onboardingStep1Title => 'Basics';

  @override
  String get onboardingStep1Blurb => 'Some basic info about you';

  @override
  String get onboardingStep2Title => 'Glucose';

  @override
  String get onboardingStep2Blurb => 'About your blood glucose and medication';

  @override
  String get onboardingStep3Title => 'Conditions';

  @override
  String get onboardingStep3Blurb => 'Chronic conditions and states';

  @override
  String get onboardingStep4Title => 'Lifestyle';

  @override
  String get onboardingStep4Blurb => 'Activity and eating habits';

  @override
  String get onboardingStep1Of4 => 'Step 1 / 4';

  @override
  String get onboardingStep2Of4 => 'Step 2 / 4';

  @override
  String get onboardingStep3Of4 => 'Step 3 / 4';

  @override
  String get onboardingStep4Of4 => 'Step 4 / 4';

  @override
  String get onboardingFieldFullName => 'Full name';

  @override
  String get onboardingFieldFullNameHint => 'Enter your name';

  @override
  String get onboardingOptional => 'Optional';

  @override
  String get onboardingRequired6 => 'Required • 6 chars';

  @override
  String get onboardingMobile => 'Mobile number';

  @override
  String get onboardingUsername => 'Username';

  @override
  String get onboardingAge => 'Age';

  @override
  String get onboardingWeight => 'Weight (kg)';

  @override
  String get onboardingHeight => 'Height (cm)';

  @override
  String get onboardingSex => 'Sex';

  @override
  String get onboardingSexMale => 'Male';

  @override
  String get onboardingSexFemale => 'Female';

  @override
  String get onboardingSexOther => 'Other';

  @override
  String get onboardingFastingGlucose => 'Fasting glucose';

  @override
  String get onboardingPostMealGlucose => 'Post-meal glucose';

  @override
  String get onboardingHba1c => 'HbA1c';

  @override
  String get onboardingMedicationLabel => 'Medication / Insulin';

  @override
  String get onboardingOnInsulin => 'I am on insulin';

  @override
  String get onboardingMedicationHint => 'Enter medication names (optional)';

  @override
  String get onboardingBp => 'Blood pressure (mmHg)';

  @override
  String get onboardingSystolic => 'Systolic';

  @override
  String get onboardingDiastolic => 'Diastolic';

  @override
  String get onboardingChronic => 'Chronic conditions';

  @override
  String get onboardingCkdLabel => 'Kidney disease (CKD)';

  @override
  String get onboardingCkdSub => 'Kidney-related foods will be limited';

  @override
  String get onboardingHeartLabel => 'Heart disease';

  @override
  String get onboardingHeartSub => 'Low-sodium and low-fat recommendations';

  @override
  String get onboardingAnemiaLabel => 'Anemia';

  @override
  String get onboardingAnemiaSub => 'Iron-rich foods will be suggested';

  @override
  String get onboardingOtherConditions => 'Other conditions';

  @override
  String get onboardingOtherConditionsHint => 'e.g.: thyroid, pregnancy…';

  @override
  String get onboardingActivity => 'Physical activity';

  @override
  String get onboardingActivityLow => 'Low';

  @override
  String get onboardingActivityModerate => 'Moderate';

  @override
  String get onboardingActivityHigh => 'High';

  @override
  String get onboardingMealSize => 'Meal size';

  @override
  String get onboardingMealSizeSmall => 'Small';

  @override
  String get onboardingMealSizeMedium => 'Medium';

  @override
  String get onboardingMealSizeLarge => 'Large';

  @override
  String get onboardingFoodPref => 'Food preference';

  @override
  String get onboardingFoodPrefOmnivore => 'Omnivore';

  @override
  String get onboardingFoodPrefVegetarian => 'Vegetarian';

  @override
  String get onboardingFoodPrefFishOnly => 'Fish only';

  @override
  String get onboardingFoodPrefNoBeef => 'No beef';

  @override
  String get onboardingDisclaimer =>
      'This information is for advice only. Please consult your doctor before making any changes.';

  @override
  String get onboardingPrevious => 'Previous';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingFinish => 'Create plan';

  @override
  String get onboardingFieldRequired => 'Required';

  @override
  String get onboardingFieldNumber => 'Enter a number';

  @override
  String get onboardingUsernameFormat => 'Username must be 6 characters';

  @override
  String get onboardingUsernameCharset =>
      'Use English letters, numbers and underscores';

  @override
  String get onboardingAgeRange => 'Age must be between 1 and 120';

  @override
  String get onboardingWeightInvalid => 'Invalid weight';

  @override
  String get onboardingHeightInvalid => 'Invalid height';

  @override
  String onboardingSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get onboardingErrNoInternet => 'No internet connection';

  @override
  String get onboardingErrNoPermission =>
      'Permission denied — refresh your session';

  @override
  String get onboardingErrOutOfRange => 'Value out of range';

  @override
  String get onboardingErrUsernameTaken =>
      'This username is already taken — choose another';

  @override
  String get onboardingErrRetry => 'Try again';

  @override
  String get onboardingWarningsTitle => 'Important';

  @override
  String get onboardingGotIt => 'Got it';

  @override
  String get authLoginTitle => 'Log in';

  @override
  String get authSignupTitle => 'Create account';

  @override
  String get authLoginSubtitle => 'Log in to your account.';

  @override
  String get authSignupSubtitle =>
      'Share a few details to get a personalized plan.';

  @override
  String get authOverlineLogin => 'Welcome back';

  @override
  String get authOverlineSignup => 'New account';

  @override
  String get authLogin => 'Log in';

  @override
  String get authSignup => 'Sign up';

  @override
  String get authFullName => 'Your name';

  @override
  String get authFullNameHint => 'e.g.: Rahim Mia';

  @override
  String get authMobile => 'Mobile number';

  @override
  String get authMobileHint => '01XXXXXXXXX';

  @override
  String get authUsername => 'Username';

  @override
  String get authUsernameHint => '6 chars (e.g.: nazmul)';

  @override
  String get authRoleQuestion => 'Are you a patient or a caregiver?';

  @override
  String get authRolePatient => 'Patient';

  @override
  String get authRoleCaregiver => 'Caregiver';

  @override
  String get authRelationship => 'Your relationship';

  @override
  String get authRelationshipHint => 'e.g.: son, husband, caregiver';

  @override
  String get authEmail => 'Email';

  @override
  String get authEmailHint => 'example@mail.com';

  @override
  String get authPassword => 'Password';

  @override
  String get authPasswordHint => 'At least 6 characters';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authShowPassword => 'Show';

  @override
  String get authHidePassword => 'Hide';

  @override
  String get authToggleToSignup => 'First time? Create a new account →';

  @override
  String get authToggleToLogin => 'Already have an account? Log in →';

  @override
  String get authBrand => 'Apon Susthota';

  @override
  String get authHeroTitle =>
      'Diabetes-friendly meals\nyour companion\nalong the way';

  @override
  String get authHeroTitleCompact => 'Diabetes-friendly meals\non your plate';

  @override
  String get authHeroSub =>
      'Personalized meal plans, daily logs and healthy recommendations — all in one place.';

  @override
  String get authHeroSubCompact => 'Personalized plans, easy tracking.';

  @override
  String get authHeroBulletLocal => 'Bangladeshi food';

  @override
  String get authHeroBulletSenior => 'Senior-friendly';

  @override
  String get authHeroBulletFree => 'Free';

  @override
  String get authConnChecking => 'Checking connection…';

  @override
  String get authConnOnline => 'Connected to server';

  @override
  String get authConnOffline => 'Connection failed — try again';

  @override
  String get authErrEmailPassword => 'Enter email and password';

  @override
  String get authErrFullName => 'Enter your name';

  @override
  String get authErrMobile => 'Enter a valid mobile number';

  @override
  String get authErrRelationship =>
      'Please enter the caregiver\'s relationship (e.g.: son).';

  @override
  String get authErrResetEmail => 'Enter your email to receive the reset link';

  @override
  String authErrResetSent(Object email) {
    return '✅ Reset link sent — check $email';
  }

  @override
  String authErrResetFailed(Object error) {
    return 'Reset failed: $error';
  }

  @override
  String authErrLoginPrefix(Object error) {
    return 'Login failed: $error';
  }

  @override
  String authErrSignupPrefix(Object error) {
    return 'Account creation failed: $error';
  }

  @override
  String get workoutHeroSectionTitle => 'Today\'s Workout';

  @override
  String get workoutProgressTitle => 'Today\'s progress';

  @override
  String get workoutProgressPctLabel => 'Overall progress';

  @override
  String get workoutStatusDone => 'Completed';

  @override
  String get workoutStatusPartial => 'Partial';

  @override
  String get workoutStatusPending => 'Not started';

  @override
  String get workoutProgressPartialSuffix => 'Almost there';

  @override
  String get workoutProgressFullSuffix => 'Target met';

  @override
  String get workoutAggregateDoneLabel => 'Completed';

  @override
  String get workoutAggregatePartialLabel => 'Partial';

  @override
  String get workoutAggregatePendingLabel => 'Remaining';

  @override
  String get workoutAggregateOfLabel => 'Total today';

  @override
  String workoutProgressOfTotal(int actual, int total, int pct) {
    return '$actual of $total min done · $pct% overall';
  }

  @override
  String workoutProgressHintPartial(int remaining) {
    return '$remaining min more to go';
  }

  @override
  String get workoutProgressHintDone => 'Today\'s target met';

  @override
  String get workoutProgressHintPending => 'Not started yet';

  @override
  String get mealProgressTitle => 'Today\'s meal progress';

  @override
  String get mealProgressPctLabel => 'Overall progress';

  @override
  String get mealStatusEaten => 'Eaten';

  @override
  String get mealStatusPending => 'Remaining';

  @override
  String get mealAggregateEatenLabel => 'Eaten';

  @override
  String get mealAggregatePendingLabel => 'Remaining';

  @override
  String mealProgressOfTotal(int eaten, int total, int pct) {
    return '$eaten of $total items eaten · $pct% overall';
  }

  @override
  String get sosTitle => 'জরুরি যোগাযোগ';

  @override
  String get sosNearestCta => 'আমার কাছের হাসপাতাল';

  @override
  String get sosHotlinesTitle => 'জাতীয় হেল্পলাইন';

  @override
  String get sosPickDivision => 'বিভাগ';

  @override
  String get sosPickDistrict => 'জেলা';

  @override
  String get sosPickUpazila => 'উপজেলা';

  @override
  String get sosCall => 'কল';

  @override
  String get sosCopy => 'কপি';

  @override
  String get sosCopied => 'নম্বর কপি হয়েছে';

  @override
  String get sosNoPermission => 'লোকেশন অনুমতি দরকার';

  @override
  String get sosNoGps => 'GPS পাওয়া যায়নি';

  @override
  String get sosNearbyEmpty => 'কাছে কোনো হাসপাতাল পাওয়া যায়নি';

  @override
  String get sosPickAny => 'যেকোনো একটি বেছে নিন';

  @override
  String get sosHospitalsInDistrict => 'এই জেলার হাসপাতাল';

  @override
  String get sosAllHospitals => 'সব হাসপাতাল';

  @override
  String sosDistanceKm(String km) {
    return '$km কিমি';
  }
}
