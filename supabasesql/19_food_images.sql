-- ---------- 19. FOOD IMAGE URLS ----------
-- Adds an optional `image_url` column to public.foods so the meal
-- checklist can render a real photo of each food instead of just an
-- icon. The column is nullable so existing rows keep working and
-- you can fill the URLs in manually (Supabase Table Editor → foods
-- → image_url column, or via a one-off UPDATE).
--
-- Once set, the app reads it through the standard select-foods query
-- used by get_daily_recommendation() / searchFoods() and renders a
-- 96 px rounded thumbnail on the left of every meal tile.

alter table public.foods
  add column if not exists image_url text;

-- (Optional) Helpful index if you ever want to filter "foods with
-- images vs without" in admin views. Cheap — text equality only.
create index if not exists foods_image_url_present_idx
  on public.foods ((image_url is not null))
  where image_url is not null;

-- No RLS change needed: image_url is part of the same row that the
-- existing "Foods are readable by any authenticated user" policy
-- already exposes. Anonymous writes stay blocked.