# Two-Role User System (Patient + Caretaker) — Completion Plan

## Context

The app `amar_diet` already has a 70%-built Patient/Caretaker two-role system. SQL schema `28` + `29` are deployed; 3 caretaker models, 1 provider, 4 caretaker screens, 1 router, and the auth-screen role picker all exist. **The role system is NOT a greenfield build — it's a completion + wiring task.**

Five gaps block the feature from working end-to-end:

1. **Compile errors** — `caretaker_shell.dart` references a missing `caretaker_inbox_tab.dart`; `patient_detail_screen.dart` references missing `log_meal_for_patient_screen.dart` and `log_dose_for_patient_screen.dart`. Debug build fails before runtime.
2. **RPC contract bugs** — three Dart methods pass wrong param shapes to working SQL RPCs.
3. **Routing not wired** — `main.dart:178` still mounts `HomeShell` directly. `RoleRouter` is built but unused; caretakers never see the caretaker shell.
4. **Patient-side inbox missing** — `getPatientPendingLinks` + `getPatientActiveCaretakers` exist in `SupabaseService`, but no widget renders them. `CaretakerProvider(variant: patient)` is never mounted.
5. **No daily/weekly/monthly charts** — `get_caretaker_daily_breakdown` + `fl_chart` (in pubspec) exist but no widget consumes them.

The intended outcome: a working two-role app where a caretaker can search, connect, monitor a patient's daily activities, drill into a monitoring dashboard with clinical data + recent activity + daily/weekly/monthly adherence charts. A patient sees incoming requests on their home + profile and can accept/decline.

---

## Phase 1 — Unblock Compilation (P0)

### 1.1 Create the missing caretaker inbox tab

**Create:** `lib/screens/caretaker/caretaker_inbox_tab.dart`

Pattern:
- Stateful widget, `Consumer<CaretakerProvider>`.
- Lists `prov.pending` (already populated by `getCaretaker_pending_requests`).
- Each row: patient full name, mobile (masked), sent-at timestamp, relationship. Action: "প্রত্যাহার" → `prov.revoke(linkId)` (already exposed on the provider).
- Bangla empty state: "এখনো কোনো অনুরোধ পাঠানো হয়নি" with violet accent (`AppColors.violet`).
- Use existing `_HeaderStrip`-style gradient header from `caretaker_today_tab.dart` for visual continuity.

**Critical:** create file at `lib/screens/caretaker/caretaker_inbox_tab.dart` (NOT in a `tabs/` subdir — the existing import in `caretaker_shell.dart:38` already specifies the flat path).

### 1.2 Create stub screens for the missing log-meal / log-dose screens

**Create:** `lib/screens/caretaker/log_meal_for_patient_screen.dart`
**Create:** `lib/screens/caretaker/log_dose_for_patient_screen.dart`

These are stubs only. Reason: `supabasesql/30_caretaker_write_passthrough.sql` is doc-only (no SQL deployed). Real write-passthrough requires new RPCs, which is a 2-3 day subtask we are deferring.

Stub pattern:
```dart
class LogMealForPatientScreen extends StatelessWidget {
  final String patientId;
  const LogMealForPatientScreen({super.key, required this.patientId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('রোগীর পক্ষে খাবার লগ')),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'শীঘ্রই আসছে — পরিচর্যাকারীর পক্ষে খাবার লগ করার জন্য SQL RPC প্রয়োজন।',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.violet.withValues(alpha: 0.8)),
      ),
    )),
  );
}
```

The buttons on `patient_detail_screen.dart` will already navigate to these via its existing imports (lines 25-26), so no edits to `patient_detail_screen.dart` are needed for compile.

### 1.3 Fix three Dart↔SQL contract bugs

**Bug A** — `lib/services/supabase_service.dart:2018-2025` — `respondCaretakerRequest` passes `p_accept: bool` but SQL expects `p_decision: text` (`'accept'|'decline'`).

```dart
// before
'p_accept': accept,
// after
'p_decision': accept ? 'accept' : 'decline',
```

**Bug B** — `lib/services/supabase_service.dart:2041-2047` — `searchPatientByMobile` passes `{'p_mobile': query}` but SQL expects `{'p_query': query}`.

```dart
// before
params: {'p_mobile': query.trim()},
// after
params: {'p_query': query.trim()},
```

**Bug C** — `lib/services/supabase_service.dart:2099-2106` — `listCaretakerPendingRequests` parses via `CaretakerLink.fromSupabaseRow` but RPC returns `link_id` (not `id`) plus wrapper fields. Fix by adding a sibling parser that maps the actual shape:

**Create:** `lib/models/caretaker_pending_request.dart` (lightweight model: `linkId, patientUserId, patientFullName, requestedAt, requestNote, caretakerRelationship`).

Then in `supabase_service.dart` `listCaretakerPendingRequests`, replace the row-from-Supabase parse with a manual JSON parse that maps `link_id → linkId`, `patient_user_id → patientUserId`, etc.

Also update `caretaker_inbox_tab.dart` (§1.1) to consume `prov.pending` as `List<CaretakerPendingRequest>` (may need a small provider tweak to expose a parallel getter).

### 1.4 Fix `caretaker_today_tab.dart` to read actual SQL keys

`get_caretaker_today_overview(p_patient uuid)` returns jsonb:
```json
{
  "patient_user_id": "...",
  "as_of_date": "2026-08-24",
  "water_liters": 1.2,
  "water_target": 2.5,
  "meals": [{ "meal_slot": "...", "status": "eaten|swap|off_plan", "impact": "...", "food_name_bn": "...", "created_at": "..." }, ...],
  "sugar": { "fasting_mmol": ..., "postprandial_mmol": ..., "random_mmol": ..., "hba1c_percent": ... },
  "bp": { "systolic_mmhg": ..., "diastolic_mmhg": ... },
  "medicine": { "taken": N, "total": N, "taken_pct": 80.0 }
}
```

The current `caretaker_today_tab.dart` reads wrong keys (`meals_eaten`, `meals_planned`, `doses_taken`, `doses_planned`, `water_ml`, `workouts_completed`, `glucose_high_flag`). Rebind to actual keys:

- Meals card → count `meals.length where status in {eaten, swap}`, planned = 3 (breakfast/lunch/dinner)
- Water card → `water_liters / water_target` with progress bar
- Glucose card → show `sugar.fasting_mmol` and `sugar.postprandial_mmol`
- BP card → show `bp.systolic_mmhg / bp.diastolic_mmhg`
- Medicine card → `medicine.taken / medicine.total` with `medicine.taken_pct`

### 1.5 Fix `CaregiverObservation.detail` type mismatch

`lib/models/caregiver_observation.dart` declares `detail: String?` but SQL `get_caretaker_recent_activities` returns `detail` as **jsonb** (e.g. `{meal_slot, food_name_bn, impact}` for meals, `{status, scheduled_time}` for medicine).

Change:
```dart
final Map<String, dynamic>? detail;  // was: String?
```

Update `caregiver_observation.dart` `fromRpcJson`:
```dart
detail: (json['detail'] is Map<String, dynamic>)
    ? json['detail'] as Map<String, dynamic>
    : null,
```

Update existing call sites in `caretaker_today_tab.dart` and `patient_detail_screen.dart` to render a map (use `detail['liters']`, `detail['food_name_bn']`, etc.) instead of a string.

### Phase 1 verification gate

- `flutter analyze` clean (zero errors).
- `flutter run` builds and launches.
- Caretaker login → CaretakerShell opens with 4 tabs. Inbox tab shows pending requests (currently empty list with empty-state message).
- Caretaker → Search tab → mobile search returns results (Bug B fix).
- Tap a search result → bottom sheet opens with relationship chooser → send request → snackbar.
- Caretaker → Patients tab → if patient accepted, patient appears. Tap → patient detail screen renders clinical grid + today card + activity feed without TypeError.

---

## Phase 2 — Wire Up Routing and Patient Inbox (P0)

### 2.1 Mount `RoleRouter` in `main.dart`

**Modify:** `lib/main.dart:175-180`

```dart
// before
home: SupabaseService.initError != null
    ? const SetupErrorScreen()
    : (_signedIn
        ? const ExitConfirmer(child: HomeShell())
        : const AuthScreen()),

// after
home: SupabaseService.initError != null
    ? const SetupErrorScreen()
    : (_signedIn
        ? const ExitConfirmer(child: RoleRouter())
        : const AuthScreen()),
```

No edits to `role_router.dart` needed — it's already built. Add `import '../screens/role_router.dart';` at the top of `main.dart`.

### 2.2 Surface patient-side inbox via banner + profile entry

The patient variant of `CaretakerProvider` already exists (`lib/services/caretaker_provider.dart:170-213` defines `_refreshPatientPending` and `_refreshPatientActive`). It just isn't mounted.

**Modify:** `lib/screens/dashboard_screen.dart` (patient dashboard, tab 0 of `HomeShell`):
- Wrap the body in a `ChangeNotifierProvider` for `CaretakerProvider(variant: CaretakerProviderVariant.patient)..attachRealtime()` (same pattern as `caretaker_shell.dart:95-99`).
- At the top of the dashboard, add a `Consumer<CaretakerProvider>` that reads `pending.length`. If > 0, render a tappable `Card` with violet accent:
  ```
  "🔔 $count জন কেয়ারটেকার অনুরোধ পাঠিয়েছেন — দেখুন"
  ```
  Tapping navigates to `PatientInboxScreen` (created in §2.3).

**Modify:** `lib/screens/profile_screen.dart` — add a row "কেয়ারটেকার অনুরোধ (X)" with a trailing badge for pending count. Same tap target.

### 2.3 Create patient inbox screen

**Create:** `lib/screens/patient/patient_inbox_screen.dart`

Pattern (reuses the caretaker inbox tab's visual style but flipped to patient accents):
- Two sections stacked: "অপেক্ষমান অনুরোধ" (pending) and "সক্রিয় পরিচর্যাকারী" (active caretakers).
- Each pending row: caretaker full name, relationship, requested_at (Bangla relative time using `intl`'s bn locale — already initialized in `main.dart:41`).
- Actions per pending row: "গ্রহণ করুন" → `provider.respondTo(linkId: id, accept: true)` → on success, refresh. "প্রত্যাখ্যান" → `accept: false`.
- Active caretakers section: read-only list (name, relationship, last_seen_at). Each row has "সরান" → `provider.revoke(linkId)`.
- Empty state in Bangla: "কোনো অনুরোধ নেই" with `AppColors.cyan` accent.
- Provider dependency: `Consumer<CaretakerProvider>` reads `pending` + `activeCaretakers` (patient variant).

### Phase 2 verification gate

- Sign up user A as patient → lands on `HomeShell` (tab 0 = dashboard).
- Sign up user B as caretaker → lands on `CaretakerShell` (tab 0 = patients).
- Caretaker B sends request to Patient A (mobile search).
- Sign back into Patient A → dashboard banner appears with count "1".
- Tap banner → PatientInboxScreen opens → shows caretaker B → tap "গ্রহণ করুন" → list refreshes, banner disappears.
- Profile screen → "Caretaker অনুরোধ" entry now shows 0 (since accepted requests moved to active).

---

## Phase 3 — Caretaker Monitoring Dashboard + Charts (P1)

### 3.1 Create the Monitoring Dashboard

**Create:** `lib/screens/caretaker/patient_monitoring_screen.dart`

This becomes the new "Drill-down" screen tapped from `patients_tab.dart`. We replace the current `PatientDetailScreen` pointer to point here (or we keep detail as a thin wrapper).

Sections, in order:
1. **Header strip** — Reuse `CaretakerHeaderStrip` pattern from `caretaker_shell.dart:124-178`. Show patient's full name, relationship, last_seen_at relative time.
2. **Today's overview grid (2×2 cards)** — Reuse the fixed card widgets from `caretaker_today_tab.dart` (from §1.4). Each card has a colored icon, label, current value, and progress indicator.
3. **Clinical snapshot strip** — Fetch via `getCaretakerClinicalSnapshot`. Render as one horizontal scrollable card list: HbA1c, fasting glucose, BP, BMI, on-insulin, CKD stage. Already exists at `_ClinicalGrid` in `patient_detail_screen.dart` — extract it into a shared widget `lib/widgets/caretaker_clinical_grid.dart` so both this dashboard and the detail view can reuse.
4. **Recent activities feed** — Fetch via `getCaretakerRecentActivities(limit: 30)`. Render `CaregiverObservation` rows using the new `Map<String, dynamic>?` detail field from §1.5. Each row: icon by `kind`, summary, contextual detail (e.g., for meal: "সকালের নাস্তা — খিচুড়ি"), relative time.
5. **AppBar action: "📊 দৈনিক/সাপ্তাহিক/মাসিক"** → navigates to the charts screen (§3.2).
6. **Floating action button row**: "রোগীর পক্ষে খাবার লগ" → push `LogMealForPatientScreen` (stub from §1.2). "রোগীর পক্ষে ওষুধ লগ" → push `LogDoseForPatientScreen` (stub from §1.2).

Update `patients_tab.dart` to navigate to `PatientMonitoringScreen` instead of `PatientDetailScreen`. Keep `PatientDetailScreen` around as a legacy alias that just wraps the new screen, OR delete it and replace all references.

### 3.2 Create daily/weekly/monthly charts screen

**Create:** `lib/screens/caretaker/caretaker_charts_screen.dart`

- Top: `SegmentedButton<int>` with labels `দৈনিক | সাপ্তাহিক | মাসিক`, values 1 / 7 / 30. Default = 7.
- Fetches via `getCaretakerDailyBreakdown(patientUserId, days: selectedDays)` on segment change.
- Three `fl_chart` widgets, each fed by the breakdown series:
  1. **Meal adherence bar chart** — `BarChart` with per-day ratio (0..1). Y-axis "0–100%". Title: "খাবার মেনে চলা".
  2. **Medicine adherence bar chart** — `BarChart` of `medicine_pct`. Title: "ওষুধ গ্রহণের হার".
  3. **Water + workout line chart** — `LineChart` with two series:
     - `water_liters` (liters/day, scaled axis 0–3 L) — `AppColors.cyan` line.
     - `workout_ratio` (0..1) — `AppColors.violet` line.
     - Title: "পানি ও ব্যায়াম".
- Each chart in its own card with a title, average-under-chart summary ("গড় ৭৮%"), and Bangla empty state when no data.
- Pull-to-refresh re-fetches.
- Use `fl_chart: ^1.0.0+` (already in `pubspec.yaml:23` — confirmed unused).

### 3.3 Wire charts into detail/dashboard

AppBar action button on `patient_monitoring_screen.dart` pushes `CaretakerChartsScreen(patientUserId: ...)`.

### Phase 3 verification gate

- As Patient A: log a few meals across 5 days in `meal_plan_screen.dart`. Log some water + a workout. Done in advance — this is seed data.
- As Caretaker B: open Patient A's monitoring dashboard.
  - Today's grid shows correct water, meals count, BP, glucose, medicine %.
  - Recent activities feed shows the logged meals + doses.
  - Clinical card strip renders.
- Tap "📊 দৈনিক/সাপ্তাহিক/মাসিক" → charts screen opens.
- Switch between segment buttons → each fetches and re-renders.
- Pull-to-refresh on dashboard triggers fresh fetch.

---

## Phase 4 — Polish (P2)

1. **Empty states everywhere** — audit every new screen. Bangla copy consistent with existing screens. Pattern: `AppColors.violet.withValues(alpha: 0.7)` icon, centered text, sentence-ending "।".
2. **Error states** — wrap every `rpc()` call in `try/catch`; on error, show Bangla snackbar "ত্রুটি হয়েছে, আবার চেষ্টা করুন" with a Retry button.
3. **`CaretakerPatientSummary` trim** — remove `mealsLast7Days`, `mealsPlannedLast7Days`, `medicineAdherence7d`, `hba1cPercent`, `fastingGlucoseMmol` fields that the SQL doesn't return. Keep `mealAdherenceToday`, `mealAdherence7d`, `medicineTodayPct` (which SQL does return). Update `patients_tab.dart` adherence pills to use the trimmed fields.
4. **`RoleChip` on patient dashboard** — add a small `RoleChip(role: UserRoleView.patient)` to the patient dashboard header for parity with the caretaker header.
5. **Realtime verification** — CaretakerProvider's realtime subscription (already wired in `attachRealtime()` at `caretaker_provider.dart:87`) should bubble new requests and accepts to both sides. Manually verify: caretaker sends request → patient immediately sees banner without manual refresh.
6. **Delete dead code** — `lib/screens/role_select_screen.dart` is unused (only the `RoleChoice` enum is imported by `role_router.dart`). Either delete the file, or extract the enum into a small utility file and delete the unused screen.

---

## Critical Files Reference

| Path | Purpose | Action |
|---|---|---|
| `lib/main.dart:175-180` | Top-level routing | Modify — mount `RoleRouter` |
| `lib/screens/caretaker/caretaker_shell.dart:38` | Imports the inbox tab | Already correct (add file) |
| `lib/screens/caretaker/caretaker_inbox_tab.dart` | **MISSING** | **Create** |
| `lib/screens/caretaker/log_meal_for_patient_screen.dart` | **MISSING** | **Create (stub)** |
| `lib/screens/caretaker/log_dose_for_patient_screen.dart` | **MISSING** | **Create (stub)** |
| `lib/screens/caretaker/caretaker_today_tab.dart` | Reads wrong JSON keys | Modify — rebind to SQL keys |
| `lib/screens/caretaker/patient_detail_screen.dart` | Imports the missing stubs | No change (stubs handle it) |
| `lib/screens/caretaker/patient_monitoring_screen.dart` | New monitoring dashboard | **Create** |
| `lib/screens/caretaker/caretaker_charts_screen.dart` | Daily/weekly/monthly charts | **Create** |
| `lib/screens/caretaker/patients_tab.dart` | List of patients; nav target | Modify — point nav at new dashboard |
| `lib/screens/caretaker/patient_search_screen.dart:197` | Reads `patient['mobile']` but SQL returns `masked_mobile` | Modify — read correct key |
| `lib/screens/patient/patient_inbox_screen.dart` | New patient inbox | **Create** |
| `lib/screens/dashboard_screen.dart` | Patient home (tab 0) | Modify — mount patient provider + add banner |
| `lib/screens/profile_screen.dart` | Profile rows | Modify — add caretaker requests row |
| `lib/services/supabase_service.dart:2018-2025` | `respondCaretakerRequest` | Modify — `p_accept` → `p_decision` |
| `lib/services/supabase_service.dart:2041-2047` | `searchPatientByMobile` | Modify — `p_mobile` → `p_query` |
| `lib/services/supabase_service.dart:2099-2106` | `listCaretakerPendingRequests` | Modify — use new `CaretakerPendingRequest` model |
| `lib/services/caretaker_provider.dart` | Patient variant | Modify — expose pending request list as `List<CaretakerPendingRequest>` |
| `lib/models/caregiver_observation.dart` | `detail` type mismatch | Modify — `String?` → `Map<String, dynamic>?` |
| `lib/models/caretaker_pending_request.dart` | New lightweight model | **Create** |
| `lib/models/caretaker_patient_summary.dart` | Trim unused fields | Modify |
| `lib/widgets/caretaker_clinical_grid.dart` | Shared clinical card strip | **Create** (extracted from `patient_detail_screen.dart`) |

---

## Verification: End-to-End Manual Test

Execute in order on Android emulator after Phase 3 completes:

1. **Patient A signup**: sign up new patient with mobile `01711111111`, role `patient`. Lands on `HomeShell` (tab 0). No banner (no requests yet).
2. **Caretaker B signup**: sign up new caretaker with mobile `01822222222`, role `caretaker`, relationship `পিতা`. Lands on `CaretakerShell` (tab 0 = empty patients list).
3. **Caretaker B → Search**: enter `01711111111` → result for Patient A → tap → bottom sheet → choose relationship → "অনুরোধ পাঠান".
4. **Caretaker B → Inbox**: request appears with "প্রত্যাহার" button.
5. **Sign back into Patient A**: dashboard shows banner "🔔 1 জন কেয়ারটেকার অনুরোধ পাঠিয়েছেন — দেখুন" (no manual refresh — realtime).
6. **Tap banner → PatientInboxScreen** → row shows Caretaker B → tap "গ্রহণ করুন" → banner disappears.
7. **Sign back into Caretaker B** → Patients tab → Patient A appears with "সংযুক্ত" status, pill showing today's adherence.
8. **Tap Patient A → Monitoring Dashboard**:
   - Today's grid shows water, meals count, BP, glucose, medicine %.
   - Recent activities feed shows the meals/doses Patient A has logged.
   - Clinical strip shows HbA1c, fasting glucose, BP, etc.
9. **Tap "📊 দৈনিক/সাপ্তাহিক/মাসিক"** → charts screen opens. Switch between segments → each fetches and re-renders with seed data.
10. **Pull-to-refresh on dashboard** → fresh data loads without app restart.
11. **Patient A logs a new meal** in `meal_plan_screen.dart` → switch back to Caretaker B's recent activities (pull-to-refresh) → new meal appears at top.

---

## Explicit Non-Goals

We are **NOT** doing any of:

- Rebuilding `auth_screen.dart` — role/relationship collection is already inline (`auth_screen.dart:478-511`).
- Rebuilding `role_router.dart` — already built, just not mounted in §2.1.
- Changing `home_shell.dart`'s structure — only adding a banner + provider mount.
- Modifying SQL — `28_*`, `29_*` are deployed. `30_*` stays doc-only until write-passthrough work.
- Implementing write-passthrough (caretaker logs meal/dose on patient's behalf) — stubs only.
- Adding Riverpod — `provider` is the locked state-management choice.
- Adding new packages — `fl_chart` is already in `pubspec.yaml`.
- Caretaker-side profile editing, notifications push, SMS OTP — out of scope.
- Patient-side feature additions beyond the inbox — patient app behavior is unchanged.
- Comprehensive charts — three charts (meal %, medicine %, water+workout) cover the user's "Daily / Weekly / Monthly" requirement.

---

## Recommendation on `30_caretaker_write_passthrough.sql`

**Defer to a future task.** Rationale:

- Currently a doc, not SQL. Implementing it requires new migrations, RLS policies, `p_logged_by` plumbing, ownership checks in `record_meal_intake` + `mark_dose`.
- The patient already logs their own meals/doses normally — caretaker write-passthrough is convenience, not a blocker.
- Stubs (§1.2) leave the UI surface in place; the real implementations can drop in later without touching `patient_detail_screen.dart`'s navigation code.

When implemented, the work is: write `supabasesql/30_caretaker_write_passthrough.sql` with passthrough RPCs (`caretaker_log_meal_for_patient`, `caretaker_log_dose_for_patient`), then replace stub bodies in `log_meal_for_patient_screen.dart` / `log_dose_for_patient_screen.dart` with real forms.
