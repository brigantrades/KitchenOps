-- Household collaboration model.
create table if not exists households (
  id uuid primary key default uuid_generate_v4(),
  name text not null default 'My Household',
  created_by uuid not null references profiles(id) on delete cascade,
  created_at timestamp with time zone default now()
);

create table if not exists household_members (
  household_id uuid not null references households(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  status text not null default 'active' check (status in ('active', 'invited')),
  invited_email text,
  created_at timestamp with time zone default now(),
  primary key (household_id, user_id)
);

create index if not exists household_members_user_idx on household_members (user_id);
create index if not exists household_members_household_idx on household_members (household_id);

alter table profiles
add column if not exists household_id uuid references households(id) on delete set null;

alter table recipes
add column if not exists household_id uuid references households(id) on delete set null;

alter table recipes
add column if not exists visibility text not null default 'personal'
check (visibility in ('personal', 'household', 'public'));

alter table meal_plan_slots
add column if not exists household_id uuid references households(id) on delete cascade;

alter table grocery_items
add column if not exists household_id uuid references households(id) on delete cascade;

-- Backfill one household per existing profile.
insert into households (id, name, created_by)
select uuid_generate_v4(), coalesce(nullif(p.name, ''), 'My Household'), p.id
from profiles p
where not exists (
  select 1
  from households h
  where h.created_by = p.id
);

update profiles p
set household_id = h.id
from households h
where h.created_by = p.id
  and p.household_id is null;

insert into household_members (household_id, user_id, role, status)
select p.household_id, p.id, 'owner', 'active'
from profiles p
where p.household_id is not null
on conflict (household_id, user_id) do nothing;

update meal_plan_slots s
set household_id = p.household_id
from profiles p
where s.user_id = p.id
  and s.household_id is null;

update grocery_items g
set household_id = p.household_id
from profiles p
where g.user_id = p.id
  and g.household_id is null;

update recipes r
set visibility = case
  when r.is_public = true then 'public'
  else 'personal'
end
where r.visibility is null
   or r.visibility = '';

alter table meal_plan_slots
alter column household_id set not null;

alter table grocery_items
alter column household_id set not null;

drop index if exists meal_plan_slots_user_week_day_order_uidx;
create unique index if not exists meal_plan_slots_household_week_day_order_uidx
on meal_plan_slots (household_id, week_start, day_of_week, slot_order);

create index if not exists recipes_household_idx on recipes (household_id);
create index if not exists recipes_visibility_idx on recipes (visibility);
create index if not exists meal_plan_slots_household_idx on meal_plan_slots (household_id);
create index if not exists grocery_items_household_idx on grocery_items (household_id);

-- Household recipe rows must have a household_id.
alter table recipes
drop constraint if exists recipes_household_visibility_check;

alter table recipes
add constraint recipes_household_visibility_check
check (
  (visibility = 'household' and household_id is not null)
  or (visibility <> 'household')
);

alter table households enable row level security;
alter table household_members enable row level security;

drop policy if exists "profiles_select_own" on profiles;
create policy "profiles_select_own" on profiles
for select using (auth.uid() = id);

drop policy if exists "profiles_write_own" on profiles;
create policy "profiles_write_own" on profiles
for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "profiles_insert_own" on profiles;
create policy "profiles_insert_own" on profiles
for insert with check (auth.uid() = id);

drop policy if exists "households_select_member" on households;
create policy "households_select_member" on households
for select using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = households.id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "households_insert_owner" on households;
create policy "households_insert_owner" on households
for insert with check (created_by = auth.uid());

drop policy if exists "households_update_member" on households;
create policy "households_update_member" on households
for update using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = households.id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
)
with check (
  exists (
    select 1
    from household_members hm
    where hm.household_id = households.id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "household_members_select_member" on household_members;
create policy "household_members_select_member" on household_members
for select using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = household_members.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "household_members_insert_member" on household_members;
create policy "household_members_insert_member" on household_members
for insert with check (
  exists (
    select 1
    from household_members hm
    where hm.household_id = household_members.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "household_members_update_member" on household_members;
create policy "household_members_update_member" on household_members
for update using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = household_members.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
)
with check (
  exists (
    select 1
    from household_members hm
    where hm.household_id = household_members.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "recipes_select_own" on recipes;
drop policy if exists "recipes_write_own" on recipes;
drop policy if exists "recipes_select_public" on recipes;

create policy "recipes_select_visibility" on recipes
for select using (
  (visibility = 'public')
  or (visibility = 'personal' and user_id = auth.uid())
  or (
    visibility = 'household'
    and exists (
      select 1
      from household_members hm
      where hm.household_id = recipes.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
);

create policy "recipes_insert_visibility" on recipes
for insert with check (
  (visibility = 'personal' and user_id = auth.uid())
  or (
    visibility = 'household'
    and user_id = auth.uid()
    and exists (
      select 1
      from household_members hm
      where hm.household_id = recipes.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
  or (visibility = 'public' and user_id = auth.uid())
);

create policy "recipes_update_visibility" on recipes
for update using (
  (visibility = 'personal' and user_id = auth.uid())
  or (
    visibility = 'household'
    and exists (
      select 1
      from household_members hm
      where hm.household_id = recipes.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
)
with check (
  (visibility = 'personal' and user_id = auth.uid())
  or (
    visibility = 'household'
    and exists (
      select 1
      from household_members hm
      where hm.household_id = recipes.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
  or (visibility = 'public' and user_id = auth.uid())
);

create policy "recipes_delete_visibility" on recipes
for delete using (
  (visibility = 'personal' and user_id = auth.uid())
  or (
    visibility = 'household'
    and exists (
      select 1
      from household_members hm
      where hm.household_id = recipes.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
);

drop policy if exists "slots_select_own" on meal_plan_slots;
drop policy if exists "slots_write_own" on meal_plan_slots;

create policy "slots_select_household" on meal_plan_slots
for select using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = meal_plan_slots.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

create policy "slots_write_household" on meal_plan_slots
for all using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = meal_plan_slots.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
)
with check (
  exists (
    select 1
    from household_members hm
    where hm.household_id = meal_plan_slots.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "grocery_select_own" on grocery_items;
drop policy if exists "grocery_write_own" on grocery_items;

create policy "grocery_select_household" on grocery_items
for select using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = grocery_items.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

create policy "grocery_write_household" on grocery_items
for all using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = grocery_items.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
)
with check (
  exists (
    select 1
    from household_members hm
    where hm.household_id = grocery_items.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

create or replace function create_household_with_member(name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  household_uuid uuid;
  actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  insert into households (name, created_by)
  values (coalesce(nullif(trim(name), ''), 'My Household'), actor)
  returning id into household_uuid;

  insert into household_members (household_id, user_id, role, status)
  values (household_uuid, actor, 'owner', 'active')
  on conflict (household_id, user_id) do nothing;

  update profiles
  set household_id = household_uuid
  where id = actor;

  return household_uuid;
end;
$$;

create or replace function invite_household_member(email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  invited_user uuid;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  select household_id
  into actor_household
  from profiles
  where id = actor;

  if actor_household is null then
    raise exception 'No active household';
  end if;

  select id into invited_user
  from auth.users
  where lower(auth.users.email) = lower(trim(email))
  limit 1;

  if invited_user is null then
    raise exception 'No account found for that email';
  end if;

  insert into household_members (household_id, user_id, role, status, invited_email)
  values (actor_household, invited_user, 'member', 'active', lower(trim(email)))
  on conflict (household_id, user_id)
  do update set status = 'active';

  update profiles
  set household_id = actor_household
  where id = invited_user
    and household_id is null;

  return invited_user;
end;
$$;

create or replace function share_selected_recipes(recipe_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  affected integer := 0;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  select household_id into actor_household from profiles where id = actor;
  if actor_household is null then
    raise exception 'No active household';
  end if;

  update recipes
  set visibility = 'household',
      household_id = actor_household
  where user_id = actor
    and id = any(recipe_ids);

  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function migrate_planner_to_household(confirm boolean default false)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  affected integer := 0;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  if confirm is not true then
    return 0;
  end if;

  select household_id into actor_household from profiles where id = actor;
  if actor_household is null then
    raise exception 'No active household';
  end if;

  update meal_plan_slots
  set household_id = actor_household
  where user_id = actor;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function migrate_grocery_to_household(confirm boolean default false)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  affected integer := 0;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  if confirm is not true then
    return 0;
  end if;

  select household_id into actor_household from profiles where id = actor;
  if actor_household is null then
    raise exception 'No active household';
  end if;

  update grocery_items
  set household_id = actor_household
  where user_id = actor;

  get diagnostics affected = row_count;
  return affected;
end;
$$;
