-- PlatePlan initial schema
create extension if not exists "uuid-ossp";

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  avatar_url text,
  goals jsonb default '[]'::jsonb,
  dietary_restrictions text[] default '{}',
  preferred_cuisines text[] default '{}',
  disliked_ingredients text[] default '{}',
  created_at timestamp with time zone default now()
);

create table if not exists recipes (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  description text,
  servings int default 2,
  prep_time int,
  cook_time int,
  meal_type text check (meal_type in ('breakfast','lunch','dinner','snack','dessert')),
  cuisine_tags text[] default '{}',
  ingredients jsonb default '[]'::jsonb,
  instructions text[] default '{}',
  image_url text,
  nutrition jsonb default '{}'::jsonb,
  is_favorite boolean default false,
  is_to_try boolean default false,
  source text,
  created_at timestamp with time zone default now()
);

create table if not exists meal_plan_slots (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  week_start date not null,
  day_of_week int not null check (day_of_week >= 0 and day_of_week <= 6),
  meal_type text not null,
  recipe_id uuid references recipes(id) on delete set null,
  servings_used int default 1,
  created_at timestamp with time zone default now(),
  unique (user_id, week_start, day_of_week, meal_type)
);

create table if not exists grocery_items (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  category text not null,
  quantity text,
  unit text,
  from_recipe_id uuid null references recipes(id) on delete set null,
  created_at timestamp with time zone default now()
);

alter table profiles enable row level security;
alter table recipes enable row level security;
alter table meal_plan_slots enable row level security;
alter table grocery_items enable row level security;

drop policy if exists "profiles_select_own" on profiles;
create policy "profiles_select_own" on profiles
for select using (auth.uid() = id);
drop policy if exists "profiles_write_own" on profiles;
create policy "profiles_write_own" on profiles
for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "recipes_select_own" on recipes;
create policy "recipes_select_own" on recipes
for select using (auth.uid() = user_id);
drop policy if exists "recipes_write_own" on recipes;
create policy "recipes_write_own" on recipes
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "slots_select_own" on meal_plan_slots;
create policy "slots_select_own" on meal_plan_slots
for select using (auth.uid() = user_id);
drop policy if exists "slots_write_own" on meal_plan_slots;
create policy "slots_write_own" on meal_plan_slots
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "grocery_select_own" on grocery_items;
create policy "grocery_select_own" on grocery_items
for select using (auth.uid() = user_id);
drop policy if exists "grocery_write_own" on grocery_items;
create policy "grocery_write_own" on grocery_items
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
