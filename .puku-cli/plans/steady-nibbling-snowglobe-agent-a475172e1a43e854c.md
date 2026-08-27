# Username Feature — Current State Audit (read-only)

Scope: every report item the user asked for. All line numbers verified against files in `C:\Users\Nazmul\StudioProjects\diabetics_meal-main`.

## 1. `lib/models/user_profile.dart` (176 lines)

- Identity (nullable): `fullName` (L5), `mobile` (L6).
- Required scalars: `age` int, `sex` String, `weightKg` double, `heightCm` double (L8–11).
- Nullable glucose/bp: `fastingGlucoseMmol`, `postMealGlucoseMmol`, `randomGlucoseMmol`, `hba1cPercent` (L13–16); `systolicBp`, `diastolicBp` (L21–22).
- Booleans with defaults: `onInsulin`, `hasCkd`, `hasHeartDisease`, `hasAnemia` (L18, 24, 27).
- Other nullable: `medication`, `ckdStage`, `otherConditions` (L19, 25, 28).
- Enums as String: `activityLevel` (low/moderate/high), `mealSizePref` (small/medium/large), `foodPreference` (omnivore/vegetarian/fish_only/no_beef) (L30–32).
- Photo: `avatarUrl` String?, `photoUploadCount` int=0 (L35, 39).
- Role: `role` String='patient', `caretakerRelationship` String? (L44, 48).
- Computed: `bmi` getter (L79).
- `toSupabaseRow(userId)` (L81–109) writes a flat snake_case map; no `fromSupabaseRow`/`fromJson` factory — just a positional constructor. Supabase read is inlined in `SupabaseService.fetchProfile` (see §3).
- `copyWith(...)` (L114–174) covers every field.
- **No `username` field anywhere.**

## 2. `lib/screens/profile_screen.dart` (729 lines)

- Editable in-screen? **None directly.** `_editProfile()` (L115) pushes `OnboardingScreen(edit: p)` (L118–121) — the onboarding form owns all editable clinical fields, not this screen.
- Form widgets: zero in this file. The screen renders read-only `_accountCard` (L400) + `_conditionsCard` (L588) and a `_CaretakerRequestsRow` (L636).
- Save handler: `MonoButton(label: 'তথ্য আপডেট করুন', onPressed: _editProfile)` (L347–351). Save actually happens inside `OnboardingScreen` → `SupabaseService.saveProfile(profile)` (see §3).
- Validation: only string trimming on `email`/`fullName` reads (L402–404); no length/regex. Auth metadata writes use `.trim()` in `SupabaseService.signUp` (not this file).
- Avatar: `_changePhoto` (L133) uploads via `uploadProfilePhoto`; gated by `maxProfilePhotoUploads = 2` (constant in service).

## 3. `lib/services/supabase_service.dart` (2476 lines)

- **Fetch**: `fetchProfile()` (L208–258). Reads the row with `select().eq('user_id', userId).maybeSingle()` and maps every column to the model inline; falls back to `auth.users.userMetadata` for `full_name`/`mobile`/`avatar_url`/`role`/`caretaker_relationship` (L220, 221, 250–256).
- **Write**: `saveProfile(UserProfile)` (L265–275). `.upsert(profile.toSupabaseRow(userId), onConflict: 'user_id')`. Throws if no user.
- **Role-only write**: `updateRoleAndRelationship` (L286–299).
- **Meta write**: `updateAccountMeta({fullName, mobile})` (L195–203) — mutates `auth.user_metadata`, not `user_profiles`.
- Other helpers touching `user_profiles` columns: `uploadProfilePhoto` writes `avatar_url` + RPC `bump_photo_upload_count` (L316–373). `pingSession` reads `user_id` only (L188–190). No username-related helper.

## 4. `supabasesql/08_signup_identity.sql` (198 lines)

- Columns added by this file: `full_name text`, `mobile text` (L11–13). Both nullable.
- Base `user_profiles` schema: `01_schema.sql` L8–35 — PK is `user_id uuid` referencing `auth.users`. RLS policy "Users manage their own profile" (L43–46) is `for all using (auth.uid() = user_id) with check (auth.uid() = user_id)`. **No unique constraints or indexes on identity columns beyond PK.**
- Trigger `on_auth_user_created after insert on auth.users` (L144–146) → `handle_new_user()` (L26–140). Copies `full_name`, `mobile`, `role`, `caretaker_relationship` from `raw_user_meta_data` and inserts with age=30/weight=60/height=160 placeholders. Idempotent via `on conflict (user_id) do update set email = excluded.email` (or `do nothing` pre-28).
- 28 added `role text not null default 'patient'` + `caretaker_relationship text` (`28_roles_and_caretaker.sql` L27–36) plus `idx_user_profiles_role` (L38–39).
- 31 added `email` column (referenced by `handle_new_user` dynamic check at L74–81 of `08_signup_identity.sql`).

## 5. `supabasesql/28_roles_and_caretaker.sql` + RLS on `user_profiles`

- **`caretaker_patient_links`** (L51–74): `id uuid PK`, `caretaker_user_id` FK→auth.users, `patient_user_id` FK→auth.users, `status` (`pending|active|declined|revoked`), `request_note`, `caretaker_relationship`, `requested_at`, `responded_at`, `last_seen_at`, `created_at`, `updated_at`.
- Unique partial index `uniq_caretaker_patient_open` on `(caretaker_user_id, patient_user_id) where status in ('pending','active')` (L81–83).
- RLS on the link table: `cp_links self read`, `cp_links caretaker insert`, `cp_links caretaker update`, `cp_links patient update` (L146–216).
- **RLS on `user_profiles`**: only the single policy in `01_schema.sql` L43–46 ("Users manage their own profile" — `for all using (auth.uid() = user_id) with check (auth.uid() = user_id)`). No additional policies exist on the table in any other file (grep `user_profiles` returned 12 files, but only `01_schema.sql`/`amar_diet_supabase_schema.sql` define policies on it; the rest are RPCs/triggers).

## 6. `lib/screens/dashboard_screen.dart` (1627 lines)

- Top-to-bottom in `_DashboardScreenState.build` (L247–299):
  1. `_ProfileHeader` (L267) — avatar + name + 3 stat tiles (workouts done / meal adherence % / day-of-30) + `_EditPill`.
  2. `_CaretakerRequestBanner` (L276) — only renders if pending requests exist.
  3. `_WaterEntryCard` (L278) — water today vs target with glass dots.
  4. `_SectionSlider` (L285) — PageView of 5 hero slides (Meal/Workout/Analytics/Medicine/Profile).
  5. `_CategoryPills` (L289) — সকাল/দুপুর/সন্ধ্যা/রাত horizontal pills.
  6. `_SectionHeader` "ক্লিনিক্যাল সারসংক্ষেপ" (L291–294).
  7. `ClinicalSnapshotCard` (L296) — final card.
- **Best fit for "Profile completion" / "Update your profile"**: directly under `_ProfileHeader` (between L267 and L275's `SizedBox(16)`) — this is the only place an inline nudging banner reads naturally without disrupting the news/blog rhythm. Alternative: bottom (after `ClinicalSnapshotCard`) if we want it out of the way until the user scrolls.
- Visual pattern for cards: `Container(padding: 14, decoration: BoxDecoration(color: AppColors.newsSurface, borderRadius: AppRadius.lg, border: Border.all(color: AppColors.newsDivider), boxShadow: AppGlass.shadow(opacity: 0.05, blur: 18, y: 6)))` — see `_WaterEntryCard` L1260–1267. Section headers use `_SectionHeader` (L1155–1188): 28 px w800 ink title + 14 px w500 muted subtitle, 6 px gap.

## 7. Grep `username` — **zero hits**

- `lib/`: no files.
- `supabasesql/`: no files.
- The feature is genuinely brand-new.

## 8. `lib/widgets/apon_susthota_shell.dart` — drawer

- `_DrawerAction` enum at L449: `enum _DrawerAction { profile, medicine, water, doctorReport, logout }` ✅ confirmed (5 members, `doctorReport` present).
- Dispatcher `_handleAction` at L151–177 handles all 5 actions.
- Drawer tile block starts inside `_DrawerColumn` build, roughly L560–615 (profile tile at L575, medicine L584, water L593, doctorReport L602, logout L613). The state library confirms tile definitions live around L575–614.
- Icon/accent pattern (L575–614): each tile is `_DrawerTile(icon: Icons.*_rounded, title: 'Bangla', subtitle: 'Bangla', accent: Color(0xRRGGBB), ...)`. Accent palette observed: medicine `0xFF059669` (emerald), water `0xFF0284C7` (sky), doctorReport `0xFF7C3AED` (violet), logout `0xFFB91C1C` (red). Pick a distinct accent for username (e.g. `0xFFDB2777` magenta or `0xFF0EA5E9` cyan) when adding a tile.

## Cross-cutting notes for the username design

- PK is `user_id`, so a UNIQUE constraint on `username` would need its own partial index `create unique index uniq_user_profiles_username on public.user_profiles (lower(username)) where username is not null` (case-insensitive to match common social-app conventions).
- `handle_new_user` (08) currently passes `age=30, weight_kg=60, height_cm=160` — it cannot derive a username from auth metadata alone, so either (a) collect in the role-select / signup screens, or (b) leave it null on signup and force a "claim your username" banner in the dashboard / profile screen.
- The only read/write paths are `fetchProfile` + `saveProfile` (+ `updateAccountMeta` for auth metadata). A new `updateUsername(String username)` RPC or a thin `SupabaseService` wrapper around `.from('user_profiles').update({'username': ...}).eq('user_id', ...)` will fit cleanly.
- `pingSession` (L188) reads one row — adding a `username` column does not affect it.
- Avatar/photo cap (`maxProfilePhotoUploads = 2`) and `bump_photo_upload_count` RPC are unrelated to username.

## Suggested next-step file touchpoints (for the plan you'll author later)

- SQL: new file `supabasesql/29b_username.sql` (or rename in sequence) — `alter table add column`, regex/length check, unique index, optional `claim_username(p_username text)` security-definer RPC for atomic case-insensitive claim.
- Dart: `UserProfile` (add `username` field + extend `toSupabaseRow`, `copyWith`, constructor) — `_username` nullable, no default.
- Service: new `SupabaseService.claimUsername(String)` and `getUsernameById(String userId)` (if you want caretakers to search by username).
- UI: a `_UsernamePromptCard` widget on the dashboard under `_ProfileHeader` when `profile.username == null`, mirroring the visual rhythm of `_WaterEntryCard`.
- Profile screen: new `_usernameRow` in `_accountCard` with an inline edit (mirrors `_rowLight` at L550).
