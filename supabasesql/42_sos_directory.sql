-- SOS / Bangladesh Emergency Medical Directory.
-- One flat reference table holding divisions, districts, upazilas,
-- national hotlines and hospitals. Read-only for the mobile app — the
-- user manages rows in Supabase Studio. Mobile never writes.
--
-- Tree shape is encoded by parent_id + kind:
--   division    -> parent_id null
--   district    -> parent_id = division.id
--   upazila     -> parent_id = district.id
--   hotline     -> parent_id null (no address / no geo)
--   hospital    -> parent_id = district.id, requires lat/lng/phone
--
-- Sort order within a parent is preserved by sort_order then name_en.

create table if not exists public.bd_emergency_entries (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('division','district','upazila','hotline','hospital')),
  parent_id   uuid references public.bd_emergency_entries(id) on delete cascade,
  slug        text not null,
  name_bn     text not null,
  name_en     text not null,
  phone       text,
  address_bn  text,
  address_en  text,
  lat         double precision,
  lng         double precision,
  type        text,
  sort_order  int  not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists uq_bd_emergency_slug_parent
  on public.bd_emergency_entries (slug, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'));

create index if not exists idx_bd_emergency_kind
  on public.bd_emergency_entries (kind);

create index if not exists idx_bd_emergency_parent
  on public.bd_emergency_entries (parent_id);

create index if not exists idx_bd_emergency_active_kind
  on public.bd_emergency_entries (active, kind);

alter table public.bd_emergency_entries enable row level security;

drop policy if exists "bd_emergency_entries read" on public.bd_emergency_entries;
create policy "bd_emergency_entries read"
  on public.bd_emergency_entries for select
  using (active = true);

grant select on public.bd_emergency_entries to anon, authenticated;

-- Convenience view: just the hospitals with geo (used by the "nearby" CTA).
create or replace view public.bd_emergency_hospitals_geo as
  select id, parent_id as district_id, name_bn, name_en, phone, lat, lng, address_bn, address_en, type
  from public.bd_emergency_entries
  where kind = 'hospital' and active = true and lat is not null and lng is not null;

grant select on public.bd_emergency_hospitals_geo to anon, authenticated;
