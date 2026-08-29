-- ════════════════════════════════════════════════════════════════════════
--  39_notifications.sql
--  App-wide notification system: news, greetings, app version pushes.
--
--  Use cases:
--   • Welcome message when user signs up.
--   • Eid / New Year / Pohela Boishakh / seasonal greetings.
--   • "New version available — please update" alerts with an external
--     Play Store / App Store URL.
--   • Feature announcements, blog/news posts with rich description
--     + image + CTA link.
--
--  Workflow for the admin (you, via Supabase Table Editor or your own
--  CMS):
--   1. Insert a row in `notifications` for every broadcast message.
--   2. Optional: insert per-user rows in `notification_deliveries`
--      if you want to control who sees what (e.g. only Bangla users).
--      If you skip this, the message is treated as a global broadcast
--      and every authenticated user sees it (filtered by `audience`).
--   3. Users open the bell icon in the app; the page lists every
--      notification they have not yet dismissed (with read/unread).
--
--  All tables are RLS-enabled. Anonymous users cannot read.
-- ════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────
-- 1.  notifications — the master broadcast / message table.
--     Each row is one piece of news you want to send to your users.
-- ──────────────────────────────────────────────────────────────────────
create table if not exists public.notifications (
  id              uuid primary key default gen_random_uuid(),

  -- Short headline (Bangla or English). Required.
  title           text not null,

  -- Optional 1–2 sentence summary that appears under the title in the
  -- notification list.
  short_message   text,

  -- Optional rich body shown when the user taps "Read more". Plain
  -- text or simple Markdown (the app renders it as plain text — no
  -- HTML stripping needed).
  long_message    text,

  -- Optional hero image URL (https://…). Stored as text so you can use
  -- any CDN or your own Supabase Storage public URL. Recommended size
  -- 1200×600 for best quality on phones.
  image_url       text,

  -- Optional tap-target URL. When the user taps the notification card
  -- we launch this URL in the device browser (or open it in-app if
  -- it is a deep link like /blog/xyz). Leave null for "informational
  -- only" notifications.
  action_url      text,

  -- Label for the CTA button on the detail card (e.g. "�পডেট করুন",
  -- "ব্লগ পড়ুন", "রেসিপি দেখুন"). Default is "Open".
  action_label    text default 'Open',

  -- What kind of notification this is. Drives the icon + color in the
  -- app and lets you filter or send targeted pushes later.
  --   announcement  → general news / feature release
  --   greeting      → Eid, New Year, birthday, etc.
  --   update        → new app version available (action_url → store)
  --   tip           → short health/nutrition tip
  --   alert         → urgent / time-sensitive
  category        text not null default 'announcement'
                  check (category in
                         ('announcement','greeting','update',
                          'tip','alert')),

  -- Audience selector. 'all' = every signed-in user sees it.
  -- 'new_users'  = users who signed up in the last 7 days.
  -- 'returning'  = users who logged in within the last 30 days but
  --                not the last 7.
  -- We use a simple text field with a check so future values are easy
  -- to add without a migration.
  audience        text not null default 'all'
                  check (audience in ('all','new_users','returning')),

  -- Priority 1 (low) → 5 (urgent). UI shows a colored dot; sort order
  -- uses this when timestamps tie.
  priority        smallint not null default 3
                  check (priority between 1 and 5),

  -- When to start showing this notification. Lets you pre-schedule
  -- greetings for a future date/time.
  starts_at       timestamptz not null default now(),

  -- Optional hard expiry. After this timestamp the notification is
  -- hidden from the user list (kept in the table for analytics).
  expires_at      timestamptz,

  -- Master kill switch — flip to false to retire a broadcast without
  -- deleting the row. The app filters out `is_active = false` rows.
  is_active       boolean not null default true,

  -- If this is a version-update notification, the version string we
  -- want the user to upgrade to. The app compares this against its
  -- own version (from package_info) and shows "Already up to date"
  -- if they match. Leave null for non-update notifications.
  target_version  text,

  -- Free-form tag list (e.g. {"eid","2026"}) so future filters can
  -- group notifications. Stored as text[]; default empty array.
  tags            text[] not null default '{}',

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists notifications_active_starts_idx
  on public.notifications (is_active, starts_at desc);
create index if not exists notifications_category_idx
  on public.notifications (category);
create index if not exists notifications_priority_idx
  on public.notifications (priority desc, created_at desc);

-- ──────────────────────────────────────────────────────────────────────
-- 2.  notification_deliveries — per-user delivery + read tracking.
--
--  A row is created lazily: when the user opens the notifications
--  page, the app inserts a delivery row for each broadcast that has
--  none yet (one row per user × notification). Subsequent reads just
--  update `read_at` / `dismissed_at`.
--
--  This design means you do NOT need to insert thousands of rows
--  when you publish a broadcast — you only write ONE row in
--  `notifications` and the deliveries are materialised on demand.
-- ──────────────────────────────────────────────────────────────────────
create table if not exists public.notification_deliveries (
  id              uuid primary key default gen_random_uuid(),
  notification_id uuid not null
                  references public.notifications(id)
                  on delete cascade,
  user_id         uuid not null
                  references auth.users(id)
                  on delete cascade,

  -- When the user first saw this notification in their list. NULL
  -- until the app has actually pulled it down at least once.
  delivered_at    timestamptz,

  -- When the user tapped the card (NULL = still unread). Used to
  -- compute the "unread count" badge on the bell icon.
  read_at         timestamptz,

  -- When the user swiped-dismissed or hit the close button. NULL
  -- means the row still appears in the list.
  dismissed_at    timestamptz,

  created_at      timestamptz not null default now(),

  -- One delivery row per (user, notification) — enforced.
  unique (notification_id, user_id)
);

create index if not exists notification_deliveries_user_idx
  on public.notification_deliveries (user_id, read_at);
create index if not exists notification_deliveries_unread_idx
  on public.notification_deliveries (user_id)
  where dismissed_at is null and read_at is null;

-- ──────────────────────────────────────────────────────────────────────
-- 3.  Row-Level Security — only authenticated users see their own
--     deliveries; only admins can write to the master table.
-- ──────────────────────────────────────────────────────────────────────
alter table public.notifications enable row level security;
alter table public.notification_deliveries enable row level security;

-- Anyone signed in can read active, non-expired notifications. This
-- powers the in-app list. Anonymous users cannot read.
drop policy if exists "notifications_select_authenticated" on public.notifications;
create policy "notifications_select_authenticated"
  on public.notifications for select
  to authenticated
  using (
    is_active = true
    and starts_at <= now()
    and (expires_at is null or expires_at > now())
  );

-- Users can read/write ONLY their own delivery rows.
drop policy if exists "notification_deliveries_select_own" on public.notification_deliveries;
create policy "notification_deliveries_select_own"
  on public.notification_deliveries for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "notification_deliveries_insert_own" on public.notification_deliveries;
create policy "notification_deliveries_insert_own"
  on public.notification_deliveries for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "notification_deliveries_update_own" on public.notification_deliveries;
create policy "notification_deliveries_update_own"
  on public.notification_deliveries for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────
-- 4.  RPC: list_active_notifications
--
--  Returns the active notifications for the current user, joining the
--  delivery row so the app can render read/unread state without
--  having to do a second round-trip.
--
--  Side effect: lazily inserts a delivery row for every active
--  notification the user has not seen yet. This is what makes the
--  "I just inserted one row in notifications and every user sees it"
--  workflow work — no admin fan-out needed.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.list_active_notifications(
  p_limit int default 50
)
returns table (
  id              uuid,
  title           text,
  short_message   text,
  long_message    text,
  image_url       text,
  action_url      text,
  action_label    text,
  category        text,
  priority        smallint,
  starts_at       timestamptz,
  expires_at      timestamptz,
  target_version  text,
  tags            text[],
  created_at      timestamptz,
  read_at         timestamptz,
  dismissed_at    timestamptz,
  delivered_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- Materialise delivery rows for any active broadcast the user
  -- hasn't seen. ON CONFLICT DO NOTHING makes this idempotent.
  insert into public.notification_deliveries
         (notification_id, user_id, delivered_at)
  select n.id, v_user, now()
    from public.notifications n
   where n.is_active = true
     and n.starts_at <= now()
     and (n.expires_at is null or n.expires_at > now())
     and not exists (
       select 1
         from public.notification_deliveries d
        where d.notification_id = n.id
          and d.user_id = v_user
     );

  -- Return the joined view. Newest first, priority as tiebreaker.
  return query
  select
    n.id, n.title, n.short_message, n.long_message,
    n.image_url, n.action_url, n.action_label,
    n.category, n.priority, n.starts_at, n.expires_at,
    n.target_version, n.tags, n.created_at,
    d.read_at, d.dismissed_at, d.delivered_at
  from public.notifications n
  join public.notification_deliveries d
    on d.notification_id = n.id
   and d.user_id = v_user
  where d.dismissed_at is null
  order by n.created_at desc, n.priority desc
  limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.list_active_notifications(int)
  to authenticated;

-- ──────────────────────────────────────────────────────────────────────
-- 5.  RPCs: mark_read / mark_dismissed / unread_count
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.mark_notification_read(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.notification_deliveries
     set read_at = coalesce(read_at, now())
   where notification_id = p_id
     and user_id = auth.uid();
$$;

grant execute on function public.mark_notification_read(uuid)
  to authenticated;

create or replace function public.mark_notification_dismissed(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.notification_deliveries
     set dismissed_at = now()
   where notification_id = p_id
     and user_id = auth.uid();
$$;

grant execute on function public.mark_notification_dismissed(uuid)
  to authenticated;

create or replace function public.unread_notification_count()
returns bigint
language sql
security definer
stable
set search_path = public
as $$
  select count(*)::bigint
    from public.notification_deliveries d
    join public.notifications n
      on n.id = d.notification_id
   where d.user_id = auth.uid()
     and d.dismissed_at is null
     and d.read_at is null
     and n.is_active = true
     and n.starts_at <= now()
     and (n.expires_at is null or n.expires_at > now());
$$;

grant execute on function public.unread_notification_count()
  to authenticated;

-- ──────────────────────────────────────────────────────────────────────
-- 6.  updated_at trigger
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists notifications_touch_updated on public.notifications;
create trigger notifications_touch_updated
  before update on public.notifications
  for each row execute function public.touch_updated_at();

-- ──────────────────────────────────────────────────────────────────────
-- 7.  Seed a few example rows so the page is non-empty in dev.
--     Feel free to delete these once you start posting real news.
-- ──────────────────────────────────────────────────────────────────────
insert into public.notifications
       (title, short_message, long_message, image_url, action_url,
        action_label, category, priority, target_version, tags)
values
  ('স্বাগতম! 🎉',
   'আপন সুস্থতা অ্যাপে আপনাকে স্বাগতম।',
   'বা�লাদেশের ডায়াবেটিস রোগীদের জন্য তৈরি এই অ্যাপে আপনাকে স্বাগতম। প্রতিদিনের খাবার পরিকল্পনা, ব্যায়াম রুটিন, ওষুধের রি�াইন্ডার এবং AI সহকারী এখন আপনার হাতের মুঠোয়।',
   null, '/dashboard', 'অন্বেষণ করুন', 'greeting', 4, null, '{welcome}'),

  ('নতুন ভার্সন �.২.০ পাওয়া যাচ্ছে',
   'দ্রুত ও আরও স্মার্ট অভিজ্ঞতার জন্য আপডেট করুন।',
   '�.২.০ ভার্সনে যা যা নতুন:\n• নতুন AI সহকারী\n• উন্নত বিশ্লেষণ ড্যাশবোর্ড\n• বাগ ফিক্স ও পারফরম্যান্স উন্নতি',
   'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif',
   'https://play.google.com/store/apps/details?id=com.amar.diet',
   'আপডেট করুন', 'update', 5, '1.2.0', '{release}'),

  ('ঈদ মোবারক! 🌙',
   'ঈদের চাঁদে ভেসে আসুক আপনার জীবনে সুখ � স্বাস্থ্য।',
   'আপন সুস্থতা পরিবারের পক্ষ থেকে আপনাকে ও আপনার পরিবারকে ঈদের অনেক অনেক শুভেচ্ছা। ঈদের সময় মিষ্টি ও ভারী খাবারের প্রতি একটু সতর্ক থাকুন — অ্যাপের মিষ্টি বিকল্প সেকশন দেখে নিন!',
   null, null, null, 'greeting', 4, null, '{eid,2026}')
on conflict do nothing;
