create table if not exists ingredient_nutrition_cache (
  id uuid primary key default gen_random_uuid(),
  normalized_name text not null,
  display_name text not null,
  fdc_id bigint,
  data_type text,
  calories_per_100g int not null,
  protein_per_100g double precision not null,
  fat_per_100g double precision not null,
  carbs_per_100g double precision not null,
  fiber_per_100g double precision not null default 0,
  sugar_per_100g double precision not null default 0,
  source text not null default 'usda_fdc',
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create unique index if not exists ingredient_nutrition_cache_normalized_name_key
  on ingredient_nutrition_cache (normalized_name);

alter table ingredient_nutrition_cache enable row level security;

drop policy if exists "ingredient_nutrition_cache_select_authenticated"
  on ingredient_nutrition_cache;
create policy "ingredient_nutrition_cache_select_authenticated"
  on ingredient_nutrition_cache
  for select
  using (auth.uid() is not null);

drop policy if exists "ingredient_nutrition_cache_insert_authenticated"
  on ingredient_nutrition_cache;
create policy "ingredient_nutrition_cache_insert_authenticated"
  on ingredient_nutrition_cache
  for insert
  with check (auth.uid() is not null);

drop policy if exists "ingredient_nutrition_cache_update_authenticated"
  on ingredient_nutrition_cache;
create policy "ingredient_nutrition_cache_update_authenticated"
  on ingredient_nutrition_cache
  for update
  using (auth.uid() is not null)
  with check (auth.uid() is not null);
