# Codebase Exploration Report — Patient/Caretaker Role System Context

**Project:** `amar_diet` (`C:/Users/Nazmul/StudioProjects/diabetics_meal-main`)
**Description:** Amar Diet — Bangladeshi diabetic meal recommendation app (Supabase backend, Bangla UI)
**Date:** 2026-08-24

> **CRITICAL CONTEXT:** This app **already ships the two-role user system** (Patient + Caretaker). The role split is the central feature of the most recent milestone. The user is planning a "major update" but most of the infrastructure they might think is missing already exists. This report makes that explicit so the implementation plan can avoid duplicating work.

---

## 1. Overall App Structure

### `pubspec.yaml` highlights
- **name:** `amar_diet`
- **description:** "Amar Diet — Bangladeshi diabetic meal recommendation app"
- **SDK:** `>=3.0.0 <4.0.0`

### Runtime dependencies (only ones that matter for this work)
| Package | Version | Purpose |
|---|---|---|
| `flutter` | sdk | – |
| `supabase_flutter` | ^2.5.6 | Backend (Auth + Postgres + Realtime + Storage) |
| `provider` | ^6.1.2 | State management |
| `intl` | ^0.19.0 | Date/number formatting, Bangla locale |
| `flutter_dotenv` | ^5.1.0 | `.env` loader for Supabase + Groq keys |
| `fl_chart` | ^1.2.0 | **Declared but currently unused** (no imports in `lib/`) |
| `auto_size_text` | ^3.0.0 | – |
| `animated_notch_bottom_bar` | 1.0.4 | Bottom nav (both shells) |
| `video_player` | ^2.9.1 | Workout video playback |
| `image_picker` | ^1.1.2 | Profile photo upload |
| `shared_preferences` | ^2.2.3 | – |
| `google_fonts` | ^6.2.1 | – |
| `pdf`, `printing` | ^3.11.1 / ^5.13.4 | Doctor report PDF |

No Riverpod, Bloc, GetIt, or freezed. No sqflite/Hive/Isar (everything is server-side via Supabase RPCs — see §3).

### `lib/` directory structure
```
lib/
├── main.dart                 # AmarDietApp + auth-state listener
├── models/                   # All in-memory models (10 patient, 3 caretaker)
├── screens/
│   ├── auth_screen.dart      # Sign-in / sign-up (role picker lives here)
│   ├── onboarding_screen.dart# Clinical intake (patient only)
│   ├── home_shell.dart       # Patient bottom-nav shell (5 tabs)
│   ├── dashboard_screen.dart
│   ├── meal_plan_screen.dart
│   ├── workout_screen.dart
│   ├── analytics_screen.dart
│   ├── ai_chat_screen.dart
│   ├── profile_screen.dart
│   ├── medicine_screen.dart
│   ├── doctor_report_screen.dart
│   ├── plan_editor.dart
│   ├── meal_details_screen.dart
│   ├── workout_details_screen.dart
│   ├── water_screen.dart
│   ├── water_analytics_screen.dart
│   ├── medicine_editor.dart
│   ├── role_router.dart      # ★ Top-level role dispatcher
│   ├── role_select_screen.dart# ★ Legacy role picker (used by _RoleSelectionDialog)
│   ├── setup_error_screen.dart
│   ├── caretaker/            # ★ Caretaker shell + 4 tabs + search
│   │   ├── caretaker_shell.dart
│   │   ├── caretaker_today_tab.dart
│   │   ├── patients_tab.dart
│   │   ├── patient_detail_screen.dart
│   │   └── patient_search_screen.dart
│   └── patient/              # ★ Empty — reserved for future per-patient screens
├── services/                 # RPC wrappers + DietRecommender + change notifiers
│   ├── supabase_service.dart # ★ All auth/profile/RPC calls (≈2,300 LOC)
│   ├── caretaker_provider.dart # ★ ChangeNotifier for caretaker state
│   ├── diet_recommender.dart
│   ├── classification_engine.dart
│   ├── impact_engine.dart
│   ├── plan_service.dart
│   ├── ai_chat_service.dart
│   ├── ai_chat_quota_cache.dart
│   ├── groq_router.dart
│   ├── water_task_scheduler.dart
│   ├── app_events.dart
│   └── env.dart
├── theme/app_theme.dart      # AppColors + AppGradients + AppMotion + AppSpacing
└── widgets/
    ├── apon_susthota_shell.dart  # AppShellScaffold (drawer + top bar)
    ├── mono_widgets.dart         # MonoButton, MonoSegmented, GradientTitle, Overline, etc.
    ├── patient_bottom_nav.dart   # ★ Patient 5-tab morphing nav
    ├── caretaker_bottom_nav.dart # ★ Caretaker 4-tab morphing nav
    ├── role_chip.dart            # ★ Persona pill used by both shells
    ├── clinical_snapshot.dart
    ├── restricted_foods_card.dart
    ├── workout_video_player.dart
    ├── inline_edit_field.dart
    └── exit_confirmer.dart
```

### State management
**`provider` (ChangeNotifier) only.** No Riverpod, Bloc, GetIt. The caretaker feature uses a single `CaretakerProvider extends ChangeNotifier` (`lib/services/caretaker_provider.dart`) that owns: patient list, pending list, selected patient, and a realtime subscription. Patient screens do **not** use a shared ChangeNotifier — they each call `SupabaseService.*` directly inside `FutureBuilder`s.

### Navigation
**Plain `Navigator 1.0`.** No `go_router`, `auto_route`, or named routes. `MaterialApp.home` is set conditionally:
```dart
home: SupabaseService.initError != null
    ? const SetupErrorScreen()
    : (_signedIn
        ? const ExitConfirmer(child: RoleRouter())  // ← actually wraps HomeShell (see §2)
        : const AuthScreen()),
```
**⚠ Note:** The current `main.dart` line 178 still uses `const ExitConfirmer(child: HomeShell())` — `RoleRouter` is defined but **not yet wired into `main.dart`**. (Plan-mode observation: confirm this discrepancy before assuming the routing is live.)

---

## 2. Authentication System

### Sign-in / sign-up
- **File:** `lib/screens/auth_screen.dart`
- **Mode:** Toggle between Login ↔ Sign-up via `MonoSegmented<bool>` (lines 432–442).
- **Sign-up fields:** name, mobile (Bangladeshi format), email, password, **role (Patient | Caretaker)**, **caretaker relationship** (only shown when role=caretaker).
- **Sign-in fields:** email + password.
- The role picker is a `MonoSegmented<String>` with options `('patient', 'রোগী')` and `('caretaker', 'পরিচর্যাকারী')` (lines 480–491). The relationship field is conditionally rendered below it (lines 492–510).

### Identity backend
**Supabase Auth** (Email/Password). Sign-up calls `SupabaseService.signUp(...)` which writes `full_name`, `mobile`, `role`, and (for caretakers) `caretaker_relationship` into `auth.users.raw_user_meta_data`:
```dart
// supabase_service.dart:149-172
static Future<AuthResponse> signUp({
  required String email,
  required String password,
  required String fullName,
  required String mobile,
  String role = 'patient',
  String? caretakerRelationship,
}) {
  final meta = <String, dynamic>{
    'full_name': fullName.trim(),
    'mobile': mobile.trim(),
    'role': role,
  };
  if (role == 'caretaker' && caretakerRelationship != null && ...) {
    meta['caretaker_relationship'] = caretakerRelationship.trim();
  }
  return client.auth.signUp(email: email, password: password, data: meta);
}
```

### Auth state listener
`lib/main.dart` lines 124–152 subscribe to `client.auth.onAuthStateChange`. On sign-in it warms the AI-chat quota cache and `WaterTaskScheduler`. On sign-out it pops to the first route.

### Existing user/account model
- **`UserProfile`** (`lib/models/user_profile.dart`) — clinical + identity profile stored in `public.user_profiles`. Includes `role` (line 44) and `caretakerRelationship` (line 48). Has `toSupabaseRow(userId)` and `copyWith`.
- **No separate "account" model** — auth info lives in `auth.users` and is mirrored via `raw_user_meta_data`. The app does **not** own a separate account table.

### Role write/read helpers
- `SupabaseService.updateRoleAndRelationship({role, caretakerRelationship})` — `lib/services/supabase_service.dart:272-285`. Single UPDATE; clears relationship on patient role.
- `SupabaseService.fetchProfile()` reads `role` + `caretaker_relationship` from `user_profiles` (with `auth.users.userMetadata` fallback) — `supabase_service.dart:194-244`.

---

## 3. Existing Health Data Models & Tracking

### Models — `lib/models/`
| File | Tracks |
|---|---|
| `user_profile.dart` | Identity + clinical + role + relationship |
| `user_meal_plan.dart` | Custom meal-plan rows (slot, time, food/custom) |
| `meal_item.dart` | Food catalogue entry (kcal, macros, GI, sodium, K, P, etc.) |
| `meal_details.dart` | Joined food + recipe |
| `medicine.dart` | Medicine, schedule slot, dose, adherence |
| `workout.dart` | Workout, assignment, session, session-item |
| `dashboard.dart` | `DashboardSummary`, `DailyNutrition`, `DailyMealLog`, `DailyMedicines` |
| `water_analytics.dart` | `WaterDayStat`, streak, bucket distribution |
| `thirty_day_report.dart` | 30-day cycle report (single JSON blob from RPC) |
| `doctor_report_input.dart` | Doctor report PDF inputs |
| `caretaker_link.dart` | ★ `CaretakerLink` + `CaretakerLinkStatus` enum (pending/active/declined/revoked) |
| `caretaker_patient_summary.dart` | ★ Slim row for the caretaker's patient list |
| `caregiver_observation.dart` | ★ Merged activity feed entry (meal/medicine/water/workout) |

### Storage layer
**100 % Supabase. No local DB (no sqflite/Hive/Isar).** All persistence is via:
1. Supabase Auth (`auth.users`) for identity.
2. Supabase Postgres tables (`public.user_profiles`, `public.meal_intake_log`, `public.medicines`, `public.medicine_doses`, `public.workout_sessions`, `public.daily_metrics`, `public.caretaker_patient_links`, …).
3. Supabase Storage buckets (`profile` for avatars, `exercise` for workout videos).
4. Realtime channels (`caretaker_link_<uid>`) for the link inbox.
5. **No `shared_preferences` usage visible in the service code I read** — the only client-side cache is `AiChatQuotaCache` (in-memory + disk via the package's own mechanism, not via `shared_preferences`).

### Data layer org
- **`lib/services/supabase_service.dart`** — one giant static class (~2,300 LOC) holding every RPC wrapper. No DAOs, no repos, no interfaces. UI screens call `SupabaseService.foo()` directly.
- **`CaretakerProvider`** (`lib/services/caretaker_provider.dart`) — the only ChangeNotifier. Wraps caretaker-related calls, owns the realtime subscription, holds patient/pending lists.
- **`AppEvents`** (`lib/services/app_events.dart`) — a tiny ChangeNotifier-based event bus used by analytics/dashboard to react to meal-logged / medicine-changed / etc. events emitted after writes.

---

## 4. Navigation & Routing

### Method
Plain `Navigator 1.0`. No `GoRouter`, no `auto_route`, no named routes, no `Navigator.popUntil` of named routes.

### Top-level flow (`main.dart` build)
```
MaterialApp
  └── home:
      ├── SetupErrorScreen        (if Supabase initError != null)
      ├── ExitConfirmer(HomeShell)   ← current code (see §1 warning)
      └── AuthScreen              (if signed out)
```

### ★ `RoleRouter` (`lib/screens/role_router.dart`) — already built, awaiting wiring
- `FutureBuilder<_RoutedShell>` decides between:
  - `_ShellKind.auth` → `AuthScreen`
  - `_ShellKind.patient` → `HomeShell(profile: ...)`
  - `_ShellKind.caretaker` → `CaretakerShell(profile: ...)`
  - `_ShellKind.needsRoleSelection` → `HomeShell` (default) + shows a one-shot dialog for legacy users whose `role` is still null.
- Reads `UserProfile.role` via `SupabaseService.fetchProfile()`. Treats both `'caretaker'` and `'caregiver'` (sic) as caretakers.

### Shells
| Shell | File | Bottom nav widget | Tabs |
|---|---|---|---|
| Patient | `lib/screens/home_shell.dart` | `PatientBottomNav` | Dashboard, Meal, Workout, Analytics, AI Assistant |
| Caretaker | `lib/screens/caretaker/caretaker_shell.dart` | `CaretakerBottomNav` | Patients, Today, Inbox, Search |

Both shells share:
- `AppShellScaffold` (`lib/widgets/apon_susthota_shell.dart`) — drawer + top bar + body + bottom bar.
- `IndexedStack` + per-tab cache (`_cache[i] ??= _buildPage(i)`) so tab state survives switches.
- `performShellLogout(context)` from the shell scaffold.

### Other key screens (all `Navigator.push(MaterialPageRoute(...))`)
- `PatientDetailScreen` (in caretaker tab → pushed from `PatientsTab` + `CaretakerTodayTab`)
- `PatientSearchScreen` (caretaker 4th tab)
- `AuthScreen` (also pushed standalone from `RoleSelectScreen`)
- `OnboardingScreen` (pushed from `ProfileScreen` for profile edits)

---

## 5. Existing Charts & Visualization

### Charting libraries
- **`fl_chart: ^1.2.0`** is declared in `pubspec.yaml`.
- **Zero Dart files import it.** `Grep` for `fl_chart | BarChart | LineChart | PieChart` across `lib/` returns no matches.
- **Visualizations currently in use are custom-painted / wrapped `Container`s**, not fl_chart widgets. Examples:
  - Weekly bars in `dashboard_screen.dart` use `LinearProgressIndicator`-style bars, not `BarChart`.
  - `WaterAnalyticsScreen` references "pie chart" in comments but the file uses a custom container layout, not `PieChart`.

### Daily / weekly / monthly view patterns
There **is** a strong daily-cycle pattern, anchored on `auth.users.created_at::date` (Sign-up Day = Day 1). See `lib/models/thirty_day_report.dart` and `lib/screens/analytics_screen.dart`. The 30-day RPC (`get_thirty_day_report()`) returns a JSON shape that the analytics screen lays out as:
- `_CycleHero` — current day number, days remaining
- `_TotalsGrid` — meal adherence %, macro averages, medicine/workout/water counts
- `_CycleInsights` — at-a-glance observations
- `_DaysList` — per-day expandable rows

The 7-day view also exists via `get_weekly_nutrition(p_days)` and `get_dashboard_summary(days: 7)`, used by `dashboard_screen.dart`.

---

## 6. Patient/Caretaker-Specific Surface (already shipped — don't duplicate)

### SQL schema (`supabasesql/28_roles_and_caretaker.sql`)
- Adds `role text not null default 'patient' check (role in ('patient','caretaker'))` to `public.user_profiles`.
- Adds `caretaker_relationship text` to `public.user_profiles`.
- Creates `public.caretaker_patient_links` with `status` (pending/active/declined/revoked).
- Enforces: cross-role link blocks (`v_caretaker_role != 'caretaker'` throws), self-link blocks.
- Partial unique index `(caretaker_user_id, patient_user_id) where status in ('pending','active')`.
- RLS: each side sees only its own rows; only caretaker INSERT; patient UPDATE respond; either side DELETE.
- Trigger broadcasts link state changes on private realtime channel per uid.

### SQL RPCs (`29_caretaker_read_rpcs.sql`, `30_caretaker_write_passthrough.sql`)
Read:
- `get_caretaker_patient_list`
- `get_caretaker_pending_requests`
- `get_caretaker_today_overview(p_patient_user_id)`
- `get_caretaker_daily_breakdown(p_patient_user_id, p_days)`
- `get_caretaker_recent_activities(p_patient_user_id, p_limit)`
- `get_caretaker_clinical_snapshot(p_patient_user_id)`
- `search_patient_by_mobile(p_query)`

Write (caretaker-on-behalf-of-patient):
- `request_caretaker_link(p_patient_user_id, p_relationship, p_note)`
- `respond_caretaker_link(p_link_id, p_accept)` — patient-side
- `revoke_caretaker_link(p_link_id)` — either side
- `record_meal_intake(..., p_logged_by)` — `caretaker_can_write_for()` helper redirects ownership.
- `mark_dose(..., p_logged_by)` — same helper.

### Client surface (already built)
| Layer | File | Purpose |
|---|---|---|
| Auth screen role picker | `lib/screens/auth_screen.dart` lines 478–511 | Sign-up captures role + relationship |
| Top-level role dispatch | `lib/screens/role_router.dart` | Decides which shell to mount |
| Legacy role dialog | `lib/screens/role_select_screen.dart` | Modal for legacy null-role users |
| Profile model | `lib/models/user_profile.dart` | `role`, `caretakerRelationship` fields |
| Patient list summary | `lib/models/caretaker_patient_summary.dart` | Read-only row shape |
| Activity feed entry | `lib/models/caregiver_observation.dart` | Merged meal/med/water/workout |
| Link row + status enum | `lib/models/caretaker_link.dart` | `CaretakerLinkStatus` (pending/active/declined/revoked) |
| Caretaker provider | `lib/services/caretaker_provider.dart` | `ChangeNotifier` with realtime, list, selection |
| RPC wrappers | `lib/services/supabase_service.dart:1985-2283` | All `*Caretaker*` + `*PatientPending*` methods |
| Patient shell | `lib/screens/caretaker/caretaker_shell.dart` | 4-tab shell with violet accent |
| Patient list tab | `lib/screens/caretaker/patients_tab.dart` | List + adherence pills |
| Caretaker Today tab | `lib/screens/caretaker/caretaker_today_tab.dart` | At-a-glance + activity feed |
| Patient detail | `lib/screens/caretaker/patient_detail_screen.dart` | Drilldown with clinical + feed + log actions |
| Search & request | `lib/screens/caretaker/patient_search_screen.dart` | Mobile-number search + relationship sheet |
| Bottom nav — patient | `lib/widgets/patient_bottom_nav.dart` | 5-tab morphing nav (cyan accent) |
| Bottom nav — caretaker | `lib/widgets/caretaker_bottom_nav.dart` | 4-tab morphing nav (violet accent) |
| Role chip | `lib/widgets/role_chip.dart` | Persona pill ("রোগী" / "কেয়ারগিভার") |

### What looks unfinished / inconsistent (worth flagging in the plan)
1. **`main.dart` still mounts `HomeShell` directly**, not `RoleRouter`. So the role-routing infrastructure exists but the entry-point is hard-coded to the patient shell. The `_signedIn` branch (line 178) needs to become `RoleRouter`.
2. **`caretaker/caretaker_inbox_tab.dart` is referenced by `caretaker_shell.dart` line 38** (`import 'caretaker_inbox_tab.dart';` and `case 2: return const CaretakerInboxTab();`) but **the file does not exist** in `lib/screens/caretaker/`. Listing confirms only `caretaker_shell.dart`, `caretaker_today_tab.dart`, `patients_tab.dart`, `patient_detail_screen.dart`, `patient_search_screen.dart`. This will fail to compile on a clean build until either the file is added or the import/case is removed.
3. **fl_chart is declared but unused** — if the user wants charting, either they want to start using fl_chart or they want to keep the custom layout.
4. **`role_select_screen.dart`** is currently imported only as a type (`show RoleChoice`) by `role_router.dart`. The screen itself is not pushed from anywhere in the active code path. Confirm with the user whether the dialog-only path is intentional or whether `RoleSelectScreen` should be reactivated as a full-screen step.
5. **`role_chip.dart` is referenced** by `caretaker_shell.dart` (line 35 import, line 173 usage) and likely by `home_shell.dart`/patient tab — verify that the patient shell actually surfaces a role chip today (the import list for `home_shell.dart` doesn't include `role_chip.dart`, so currently only the caretaker shell shows the chip).

---

## TL;DR for the implementation plan

**Almost everything the user described already exists.** Before designing "where to plug in the new Patient/Caretaker role system", the implementation plan needs to:

1. **Decide whether the user is unaware of the existing system** (most likely — they asked for an introduction) **or is planning an iteration on it** (rename, expand, etc.). Ask the user.
2. **If unaware:** the implementation plan should pivot to "finish wiring what exists" — fix the 5 gaps listed above. Specifically: wire `RoleRouter` into `main.dart`, add the missing `caretaker_inbox_tab.dart`, decide what to do with `role_select_screen.dart`, optionally surface the role chip in the patient shell, and start using fl_chart if charts are wanted.
3. **If iterating:** identify the delta. Existing screens to keep: `role_router.dart`, `role_select_screen.dart`, `caretaker/*`, the role picker in `auth_screen.dart`, `UserProfile.role`/`caretakerRelationship`, all caretaker SQL/RPCs.

**Files most likely to need changes for any iteration:**
- `lib/main.dart` — wire `RoleRouter`.
- `lib/screens/caretaker/` — add missing `caretaker_inbox_tab.dart`.
- `lib/screens/auth_screen.dart` — role picker UI (if changing UX).
- `lib/services/supabase_service.dart` — caretaking RPC wrappers (if extending scope).
- `lib/services/caretaker_provider.dart` — selection / state model (if extending scope).
- `lib/models/user_profile.dart`, `lib/models/caretaker_link.dart`, `lib/models/caretaker_patient_summary.dart`, `lib/models/caregiver_observation.dart` — if new fields are needed.
- `lib/widgets/role_chip.dart`, `lib/widgets/patient_bottom_nav.dart`, `lib/widgets/caretaker_bottom_nav.dart` — visual changes.
- `supabasesql/28_roles_and_caretaker.sql`, `29_caretaker_read_rpcs.sql`, `30_caretaker_write_passthrough.sql` — any new server-side surface.

