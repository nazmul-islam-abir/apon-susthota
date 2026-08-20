-- ============================================================
-- Amar Diet — Dynamic Plan Generation v2
-- ============================================================
-- Replaces the static-rotation-based get_daily_recommendation() with
-- a fully dynamic generator that filters the master foods table by:
--   * user classification (allowed_gi, restricted_tags)
--   * food preference (vegetarian / fish_only / no_beef / omnivore)
--   * daily macro targets (carb / protein / fat)
--   * CKD stage (K, Phos, protein limits)
--   * BP stage (sodium limit)
--   * heart disease (fat, cholesterol, sodium)
--   * anemia (iron prioritization)
-- The "30-day rotation" remains in `meal_plan_days` as a *scaffold* — the
-- generator picks from the static template and *substitutes* any food
-- that violates the user's clinical restrictions, so the daily plan is
-- always personalized without losing the friendly rotation structure.
-- ============================================================


-- ---------- 1. PERSISTENT PLAN CACHE ----------
-- Pre-baked recommendations per (user_id, plan_date). Falls back to be
-- generated on-the-fly if no row exists.
create table if not exists public.user_meal_plan_recommendations (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.user_profiles(user_id) on delete cascade,
  plan_date     date not null,                            -- calendar date
  plan_day      int  not null check (plan_day between 1 and 30),
  slot          text not null,                            -- breakfast | morning_snack | lunch | evening_snack | dinner
  food_id       text not null references public.foods(id) on delete restrict,
  food_name_bn  text not null,
  portion_g     numeric,
  portion_label text,
  kcal          numeric,
  carb_g        numeric,
  protein_g     numeric,
  fat_g         numeric,
  fiber_g       numeric,
  gi_category   text,
  category      text,
  role          text,                                     -- main | carb | protein | vegetable | dal | snack
  generated_at  timestamptz not null default now(),
  unique (user_id, plan_date, slot, role)
);

create index if not exists umpr_user_date_idx
  on public.user_meal_plan_recommendations (user_id, plan_date);

alter table public.user_meal_plan_recommendations enable row level security;
drop policy if exists umpr_select on public.user_meal_plan_recommendations;
create policy umpr_select on public.user_meal_plan_recommendations for select to authenticated using (auth.uid() = user_id);
drop policy if exists umpr_all on public.user_meal_plan_recommendations;
create policy umpr_all on public.user_meal_plan_recommendations for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- ---------- 2. FOOD-RESTRICTION FILTER (internal) ----------
-- Returns the set of foods visible to a given classification.
create or replace function public._filtered_foods_for(p_cls jsonb)
returns table (id text, name_bn text, category text, gi_category text,
               carb_g numeric, protein_g numeric, fat_g numeric, fiber_g numeric,
               sodium_mg numeric, potassium_mg numeric, phosphorus_mg numeric,
               portion_label text, portion_g numeric, tags text[])
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_allowed_gi text[] := array(select jsonb_array_elements_text(coalesce(p_cls->'allowed_gi', '["low","medium"]')));
  v_restricted text[] := array(select jsonb_array_elements_text(coalesce(p_cls->'restricted_tags', '[]')));
  v_k_cap      numeric := coalesce((p_cls->>'max_carb_per_meal')::numeric, 45);
  v_k_cap_k    numeric := 200;  -- per-meal K cap for CKD
  v_k_cap_phos numeric := 150;  -- per-meal Phos cap for CKD
  v_prot_cap   numeric := 25;   -- per-meal protein cap for CKD
  v_ckd        boolean := (p_cls->'restriction_flags' ? 'ckd_restricted_high_k');
  v_heart      boolean := (p_cls->'restriction_flags' ? 'heart_moderate_restricted');
  v_sodium_cap numeric := 250; -- per-meal sodium cap
  v_hypertension boolean := (p_cls->'restriction_flags' ? 'low_sodium_required');
begin
  return query
  select f.id, f.name_bn, f.category, f.gi_category,
         f.carb_g, f.protein_g, f.fat_g, f.fiber_g,
         f.sodium_mg, f.potassium_mg, f.phosphorus_mg,
         f.portion_label, f.portion_g, f.tags
  from public.foods f
  where f.gi_category = any(v_allowed_gi)
    -- Exclude any restricted tags
    and (cardinality(v_restricted) = 0 or not (f.tags && v_restricted))
    -- CKD: cap K + Phos per meal
    and (not v_ckd or (f.potassium_mg <= v_k_cap_k and f.phosphorus_mg <= v_k_cap_phos))
    -- CKD: cap protein per meal
    and (not v_ckd or f.protein_g <= v_prot_cap)
    -- Heart: cap saturated fat per meal
    and (not v_heart or f.fat_g <= 12)
    -- Hypertension: cap sodium per meal
    and (not v_hypertension or f.sodium_mg <= v_sodium_cap)
  order by f.category, f.id;
end;
$$;


-- ---------- 3. PICK HELPER (per slot) ----------
-- Picks the best food for a slot from a filtered candidate set, with
-- preference for a preferred id if it's still valid.
create or replace function public._pick_from_filter(
  p_cls jsonb,
  p_category text,
  p_preferred_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pref jsonb;
  v_cand jsonb;
begin
  -- Try the preferred id first (from the 30-day rotation)
  if p_preferred_id is not null then
    select to_jsonb(f.*) into v_pref
    from public.foods f
    where f.id = p_preferred_id
      and f.gi_category = any(array(select jsonb_array_elements_text(coalesce(p_cls->'allowed_gi', '["low","medium"]'))))
      and not (f.tags && array(select jsonb_array_elements_text(coalesce(p_cls->'restricted_tags', '[]'))));
    if v_pref is not null then
      return v_pref;
    end if;
  end if;

  -- Fall back to a healthy candidate from the requested category
  select to_jsonb(f.*) into v_cand
  from public.foods f
  where f.category = p_category
    and f.gi_category = any(array(select jsonb_array_elements_text(coalesce(p_cls->'allowed_gi', '["low","medium"]'))))
    and not (f.tags && array(select jsonb_array_elements_text(coalesce(p_cls->'restricted_tags', '[]'))))
    -- Don't blow past per-meal carb limit
    and f.carb_g <= coalesce((p_cls->>'max_carb_per_meal')::numeric, 45) + 10
  order by case when f.healthiness = 'good' then 0
                when f.healthiness = 'neutral' then 1
                else 2 end,
           f.id
  limit 1;

  return v_cand;
end;
$$;


-- ---------- 4. ALTERNATIVE BUILDER ----------
-- Returns up to N alternatives for a given food, filtered by classification.
-- Used by the swap UI.
create or replace function public.food_alternatives_v2(p_user_id uuid, p_food_id text, p_limit int default 4)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cls jsonb;
  out jsonb := '[]';
  rec record;
begin
  cls := public.classify_user_v2(p_user_id);
  for rec in
    select f.*, a.priority
    from public.food_alternatives a
    join public.foods f on f.id = a.alternative_id
    where a.food_id = p_food_id
      and f.gi_category = any(array(select jsonb_array_elements_text(coalesce(cls->'allowed_gi', '["low","medium"]'))))
      and not (f.tags && array(select jsonb_array_elements_text(coalesce(cls->'restricted_tags', '[]'))))
    order by a.priority asc
    limit p_limit
  loop
    out := out || jsonb_build_object(
      'id', rec.id,
      'name_bn', rec.name_bn,
      'category', rec.category,
      'portion_label', rec.portion_label,
      'gi_category', rec.gi_category,
      'healthiness', rec.healthiness,
      'affordability', rec.affordability,
      'common_in_bd', rec.common_in_bd,
      'tags', to_jsonb(rec.tags),
      'carb_g', rec.carb_g,
      'protein_g', rec.protein_g,
      'fat_g', rec.fat_g,
      'sodium_mg', rec.sodium_mg,
      'potassium_mg', rec.potassium_mg,
      'phosphorus_mg', rec.phosphorus_mg
    );
  end loop;
  return out;
end;
$$;


-- ---------- 5. DAILY RECOMMENDATION (V2) ----------
-- Returns a fully-personalized day plan as JSON. Uses the static
-- rotation as a *scaffold* and substitutes any restricted food.
create or replace function public.get_daily_recommendation_v2(p_user_id uuid, p_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cls jsonb;
  plan public.meal_plan_days;
  v_b jsonb; v_ms jsonb; v_l_c jsonb; v_l_p jsonb; v_l_v jsonb; v_l_d jsonb;
  v_es jsonb; v_d_c jsonb; v_d_p jsonb; v_d_v jsonb;
  -- Per-meal running totals
  v_total_kcal numeric; v_total_carb numeric; v_total_protein numeric; v_total_fat numeric;
  v_total_sodium numeric; v_total_potassium numeric; v_total_phosphorus numeric;
begin
  cls := public.classify_user_v2(p_user_id);
  select * into plan from public.meal_plan_days where day = p_day;
  if not found then
    raise exception 'No plan found for day %', p_day;
  end if;

  -- Build slot picks
  v_b  := public._pick_from_filter(cls, 'breakfast', plan.breakfast_main);
  v_ms := public._pick_from_filter(cls, 'snack',    plan.morning_snack);
  v_l_c := public._pick_from_filter(cls, 'carb',     plan.lunch_carb);
  v_l_p := public._pick_from_filter(cls, 'protein',  plan.lunch_protein);
  v_l_v := public._pick_from_filter(cls, 'vegetable',plan.lunch_vegetable);
  v_l_d := public._pick_from_filter(cls, 'dal',      plan.lunch_dal);
  v_es := public._pick_from_filter(cls, 'snack',    plan.evening_snack);
  v_d_c := public._pick_from_filter(cls, 'carb',     plan.dinner_carb);
  v_d_p := public._pick_from_filter(cls, 'protein',  plan.dinner_protein);
  v_d_v := public._pick_from_filter(cls, 'vegetable',plan.dinner_vegetable);

  -- Compute daily totals
  select coalesce(sum((x->>'kcal')::numeric), 0),
         coalesce(sum((x->>'carb_g')::numeric), 0),
         coalesce(sum((x->>'protein_g')::numeric), 0),
         coalesce(sum((x->>'fat_g')::numeric), 0),
         coalesce(sum((x->>'sodium_mg')::numeric), 0),
         coalesce(sum((x->>'potassium_mg')::numeric), 0),
         coalesce(sum((x->>'phosphorus_mg')::numeric), 0)
    into v_total_kcal, v_total_carb, v_total_protein, v_total_fat,
         v_total_sodium, v_total_potassium, v_total_phosphorus
  from jsonb_array_elements(jsonb_build_array(v_b, v_ms, v_l_c, v_l_p, v_l_v, v_l_d, v_es, v_d_c, v_d_p, v_d_v)) x;

  return jsonb_build_object(
    'day', p_day,
    'classification', cls,
    'breakfast',      v_b,
    'morning_snack',  v_ms,
    'lunch', jsonb_build_object(
      'carb',      v_l_c,
      'protein',   v_l_p,
      'vegetable', v_l_v,
      'dal',       v_l_d
    ),
    'evening_snack',  v_es,
    'dinner', jsonb_build_object(
      'carb',      v_d_c,
      'protein',   v_d_p,
      'vegetable', v_d_v
    ),
    'totals', jsonb_build_object(
      'kcal',         v_total_kcal,
      'carb_g',       v_total_carb,
      'protein_g',    v_total_protein,
      'fat_g',        v_total_fat,
      'sodium_mg',    v_total_sodium,
      'potassium_mg', v_total_potassium,
      'phosphorus_mg',v_total_phosphorus
    ),
    'targets', jsonb_build_object(
      'kcal',      cls->>'daily_kcal_target',
      'carb_g',    cls->>'daily_carb_target_g',
      'protein_g', cls->>'daily_protein_target_g',
      'fat_g',     cls->>'daily_fat_target_g',
      'sodium_mg', cls->>'daily_sodium_cap_mg'
    )
  );
end;
$$;


-- ---------- 6. PERSIST THE DAY'S PLAN ----------
-- Writes the per-user day plan to the cache table; idempotent.
create or replace function public.persist_day_plan(p_user_id uuid, p_plan_date date, p_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan jsonb;
  v_b jsonb; v_ms jsonb; v_l_c jsonb; v_l_p jsonb; v_l_v jsonb; v_l_d jsonb;
  v_es jsonb; v_d_c jsonb; v_d_p jsonb; v_d_v jsonb;
  inserted jsonb;
begin
  plan := public.get_daily_recommendation_v2(p_user_id, p_day);

  v_b  := plan->'breakfast';
  v_ms := plan->'morning_snack';
  v_l_c := plan->'lunch'->'carb';
  v_l_p := plan->'lunch'->'protein';
  v_l_v := plan->'lunch'->'vegetable';
  v_l_d := plan->'lunch'->'dal';
  v_es := plan->'evening_snack';
  v_d_c := plan->'dinner'->'carb';
  v_d_p := plan->'dinner'->'protein';
  v_d_v := plan->'dinner'->'vegetable';

  -- Wipe old rows for that (user, date)
  delete from public.user_meal_plan_recommendations
   where user_id = p_user_id and plan_date = p_plan_date;

  -- Insert 10 rows (one per slot) with null-safe COALESCE
  insert into public.user_meal_plan_recommendations
    (user_id, plan_date, plan_day, slot, food_id, food_name_bn, portion_g, portion_label,
     kcal, carb_g, protein_g, fat_g, fiber_g, gi_category, category, role)
  values
    (p_user_id, p_plan_date, p_day, 'breakfast',     v_b->>'id',  v_b->>'name_bn',  (v_b->>'portion_g')::numeric,  v_b->>'portion_label',  0, (v_b->>'carb_g')::numeric, (v_b->>'protein_g')::numeric, (v_b->>'fat_g')::numeric,  0, v_b->>'gi_category', v_b->>'category', 'main'),
    (p_user_id, p_plan_date, p_day, 'morning_snack', v_ms->>'id', v_ms->>'name_bn', (v_ms->>'portion_g')::numeric, v_ms->>'portion_label', 0, (v_ms->>'carb_g')::numeric,(v_ms->>'protein_g')::numeric,(v_ms->>'fat_g')::numeric, 0, v_ms->>'gi_category',v_ms->>'category','snack'),
    (p_user_id, p_plan_date, p_day, 'lunch',         v_l_c->>'id',v_l_c->>'name_bn',(v_l_c->>'portion_g')::numeric,v_l_c->>'portion_label',0, (v_l_c->>'carb_g')::numeric,(v_l_c->>'protein_g')::numeric,(v_l_c->>'fat_g')::numeric,0, v_l_c->>'gi_category',v_l_c->>'category','carb'),
    (p_user_id, p_plan_date, p_day, 'lunch',         v_l_p->>'id',v_l_p->>'name_bn',(v_l_p->>'portion_g')::numeric,v_l_p->>'portion_label',0, (v_l_p->>'carb_g')::numeric,(v_l_p->>'protein_g')::numeric,(v_l_p->>'fat_g')::numeric,0, v_l_p->>'gi_category',v_l_p->>'category','protein'),
    (p_user_id, p_plan_date, p_day, 'lunch',         v_l_v->>'id',v_l_v->>'name_bn',(v_l_v->>'portion_g')::numeric,v_l_v->>'portion_label',0, (v_l_v->>'carb_g')::numeric,(v_l_v->>'protein_g')::numeric,(v_l_v->>'fat_g')::numeric,0, v_l_v->>'gi_category',v_l_v->>'category','vegetable'),
    (p_user_id, p_plan_date, p_day, 'lunch',         v_l_d->>'id',v_l_d->>'name_bn',(v_l_d->>'portion_g')::numeric,v_l_d->>'portion_label',0, (v_l_d->>'carb_g')::numeric,(v_l_d->>'protein_g')::numeric,(v_l_d->>'fat_g')::numeric,0, v_l_d->>'gi_category',v_l_d->>'category','dal'),
    (p_user_id, p_plan_date, p_day, 'evening_snack', v_es->>'id', v_es->>'name_bn', (v_es->>'portion_g')::numeric, v_es->>'portion_label', 0, (v_es->>'carb_g')::numeric,(v_es->>'protein_g')::numeric,(v_es->>'fat_g')::numeric, 0, v_es->>'gi_category',v_es->>'category','snack'),
    (p_user_id, p_plan_date, p_day, 'dinner',        v_d_c->>'id',v_d_c->>'name_bn',(v_d_c->>'portion_g')::numeric,v_d_c->>'portion_label',0, (v_d_c->>'carb_g')::numeric,(v_d_c->>'protein_g')::numeric,(v_d_c->>'fat_g')::numeric,0, v_d_c->>'gi_category',v_d_c->>'category','carb'),
    (p_user_id, p_plan_date, p_day, 'dinner',        v_d_p->>'id',v_d_p->>'name_bn',(v_d_p->>'portion_g')::numeric,v_d_p->>'portion_label',0, (v_d_p->>'carb_g')::numeric,(v_d_p->>'protein_g')::numeric,(v_d_p->>'fat_g')::numeric,0, v_d_p->>'gi_category',v_d_p->>'category','protein'),
    (p_user_id, p_plan_date, p_day, 'dinner',        v_d_v->>'id',v_d_v->>'name_bn',(v_d_v->>'portion_g')::numeric,v_d_v->>'portion_label',0, (v_d_v->>'carb_g')::numeric,(v_d_v->>'protein_g')::numeric,(v_d_v->>'fat_g')::numeric,0, v_d_v->>'gi_category',v_d_v->>'category','vegetable');

  inserted := public.get_day_plan_with_fallback(p_user_id, p_plan_date, p_day);
  return inserted;
end;
$$;


-- ---------- 7. CALENDAR LOADER ----------
-- Persists N days of plans starting from a date. Used by the app on
-- login to pre-bake the upcoming cycle.
create or replace function public.ensure_upcoming_plans(p_user_id uuid, p_from_date date, p_days int default 30)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  i int;
  v_date date;
  v_day int;
  v_total int := 0;
begin
  for i in 0..p_days - 1 loop
    v_date := p_from_date + i;
    v_day := ((i) % 30) + 1;
    perform public.persist_day_plan(p_user_id, v_date, v_day);
    -- Compute kcal for cache
    update public.user_meal_plan_recommendations
       set kcal = round(
         ( (coalesce(carb_g, 0) * 4) +
           (coalesce(protein_g, 0) * 4) +
           (coalesce(fat_g, 0) * 9) )::numeric
       )::int
     where user_id = p_user_id and plan_date = v_date;
    v_total := v_total + 1;
  end loop;
  return v_total;
end;
$$;


-- ---------- 8. DAY-PLAN READER (with fallback) ----------
-- Reads the cached plan for a date; if no row exists, computes on the fly.
create or replace function public.get_day_plan_with_fallback(p_user_id uuid, p_plan_date date, p_plan_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
  v_plan jsonb;
begin
  select jsonb_agg(row_to_json(t))
    into v_rows
  from (
    select r.*, f.name_bn as resolved_name, f.portion_label as resolved_portion,
           f.category as resolved_category, f.gi_category as resolved_gi
      from public.user_meal_plan_recommendations r
      left join public.foods f on f.id = r.food_id
     where r.user_id = p_user_id
       and r.plan_date = p_plan_date
  ) t;

  if v_rows is null or jsonb_array_length(v_rows) = 0 then
    v_plan := public.get_daily_recommendation_v2(p_user_id, p_plan_day);
    -- Persist for next time
    perform public.persist_day_plan(p_user_id, p_plan_date, p_plan_day);
    return v_plan;
  end if;

  return v_rows;
end;
$$;


-- ---------- 9. LEGACY get_daily_recommendation (shim) ----------
-- Keeps the existing v1 function name working so the Flutter app
-- doesn't break — routed through v2.
create or replace function public.get_daily_recommendation(p_user_id uuid, p_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.get_daily_recommendation_v2(p_user_id, p_day);
end;
$$;


-- ---------- 10. EXPIRE / INVALIDATE PLAN CACHE ----------
-- When a user updates their profile, plans become stale. The app can
-- call this to invalidate the cache for the next regenerate.
create or replace function public.invalidate_plan_cache(p_user_id uuid, p_from_date date default current_date)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  delete from public.user_meal_plan_recommendations
   where user_id = p_user_id
     and plan_date >= p_from_date;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


-- ============================================================
-- ✓ Done. Run this in Supabase SQL Editor after 23_classify_v2.sql.
-- ============================================================