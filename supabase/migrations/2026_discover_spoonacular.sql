-- Discover public Spoonacular recipe support
alter table recipes
add column if not exists is_public boolean default false;

alter table recipes
add column if not exists source text default 'user';

alter table recipes
add column if not exists api_id text;

alter table recipes
add column if not exists nutrition jsonb default '{}'::jsonb;

alter table recipes
add column if not exists nutrition_source text default 'spoonacular';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'recipes_api_id_key'
  ) then
    alter table recipes
    add constraint recipes_api_id_key unique (api_id);
  end if;
end $$;

create index if not exists recipes_public_meal_type_idx
on recipes (is_public, meal_type);

create index if not exists recipes_cuisine_tags_gin_idx
on recipes using gin (cuisine_tags);

drop policy if exists "recipes_select_public" on recipes;
create policy "recipes_select_public" on recipes
for select using (is_public = true);
