-- Leckerly epic foundation: planner flexibility, lists, visibility normalization,
-- and notification event scaffolding.

-- 1) Meal planner slot flexibility (free-text meal + optional sauce recipe/text).
alter table meal_plan_slots
add column if not exists meal_text text;

alter table meal_plan_slots
add column if not exists sauce_recipe_id uuid references recipes(id) on delete set null;

alter table meal_plan_slots
add column if not exists sauce_text text;

-- 2) Normalize public/private recipe behavior.
alter table recipes
add column if not exists is_public boolean default false;

alter table recipes
drop constraint if exists recipes_meal_type_check;

update recipes
set meal_type = case
  when meal_type = 'breakfast' then 'entree'
  when meal_type = 'lunch' then 'side'
  when meal_type = 'dinner' then 'sauce'
  else meal_type
end;

alter table recipes
add constraint recipes_meal_type_check
check (meal_type in ('entree', 'side', 'sauce', 'snack', 'dessert'));

update recipes
set visibility = 'public'
where is_public = true;

update recipes
set is_public = true
where visibility = 'public';

create or replace function sync_recipe_public_visibility()
returns trigger
language plpgsql
as $$
begin
  if new.visibility = 'public' then
    new.is_public := true;
  elsif coalesce(new.is_public, false) = true then
    new.visibility := 'public';
  else
    new.is_public := false;
  end if;
  return new;
end;
$$;

drop trigger if exists recipes_sync_public_visibility on recipes;
create trigger recipes_sync_public_visibility
before insert or update on recipes
for each row
execute function sync_recipe_public_visibility();

-- 3) Lists and list_items tables (replacing single grocery list semantics).
create table if not exists lists (
  id uuid primary key default uuid_generate_v4(),
  owner_user_id uuid not null references profiles(id) on delete cascade,
  household_id uuid references households(id) on delete cascade,
  name text not null,
  kind text not null default 'general',
  scope text not null check (scope in ('private', 'household')),
  created_at timestamp with time zone default now()
);

create table if not exists list_items (
  id uuid primary key default uuid_generate_v4(),
  list_id uuid not null references lists(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  notes text,
  category text not null default 'other',
  quantity text,
  unit text,
  from_recipe_id uuid references recipes(id) on delete set null,
  source_type text not null default 'manual',
  source_slot_id uuid references meal_plan_slots(id) on delete set null,
  status text not null default 'open' check (status in ('open', 'done')),
  created_at timestamp with time zone default now()
);

create index if not exists lists_owner_idx on lists (owner_user_id);
create index if not exists lists_household_scope_idx on lists (household_id, scope);
create index if not exists list_items_list_idx on list_items (list_id, created_at);
create index if not exists list_items_recipe_idx on list_items (from_recipe_id);

alter table lists enable row level security;
alter table list_items enable row level security;

drop policy if exists "lists_select_access" on lists;
create policy "lists_select_access" on lists
for select using (
  (scope = 'private' and owner_user_id = auth.uid())
  or (scope = 'household' and is_household_member(household_id))
);

drop policy if exists "lists_insert_access" on lists;
create policy "lists_insert_access" on lists
for insert with check (
  owner_user_id = auth.uid()
  and (
    (scope = 'private' and household_id is null)
    or (scope = 'household' and is_household_member(household_id))
  )
);

drop policy if exists "lists_update_access" on lists;
create policy "lists_update_access" on lists
for update using (
  owner_user_id = auth.uid()
  or (scope = 'household' and is_household_member(household_id))
)
with check (
  owner_user_id = auth.uid()
  or (scope = 'household' and is_household_member(household_id))
);

drop policy if exists "lists_delete_access" on lists;
create policy "lists_delete_access" on lists
for delete using (
  owner_user_id = auth.uid()
  or (scope = 'household' and is_household_member(household_id))
);

drop policy if exists "list_items_select_access" on list_items;
create policy "list_items_select_access" on list_items
for select using (
  exists (
    select 1
    from lists l
    where l.id = list_items.list_id
      and (
        (l.scope = 'private' and l.owner_user_id = auth.uid())
        or (l.scope = 'household' and is_household_member(l.household_id))
      )
  )
);

drop policy if exists "list_items_insert_access" on list_items;
create policy "list_items_insert_access" on list_items
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1
    from lists l
    where l.id = list_items.list_id
      and (
        (l.scope = 'private' and l.owner_user_id = auth.uid())
        or (l.scope = 'household' and is_household_member(l.household_id))
      )
  )
);

drop policy if exists "list_items_update_access" on list_items;
create policy "list_items_update_access" on list_items
for update using (
  exists (
    select 1
    from lists l
    where l.id = list_items.list_id
      and (
        (l.scope = 'private' and l.owner_user_id = auth.uid())
        or (l.scope = 'household' and is_household_member(l.household_id))
      )
  )
)
with check (
  exists (
    select 1
    from lists l
    where l.id = list_items.list_id
      and (
        (l.scope = 'private' and l.owner_user_id = auth.uid())
        or (l.scope = 'household' and is_household_member(l.household_id))
      )
  )
);

drop policy if exists "list_items_delete_access" on list_items;
create policy "list_items_delete_access" on list_items
for delete using (
  exists (
    select 1
    from lists l
    where l.id = list_items.list_id
      and (
        (l.scope = 'private' and l.owner_user_id = auth.uid())
        or (l.scope = 'household' and is_household_member(l.household_id))
      )
  )
);

-- Backfill one default household list and migrate grocery_items into list_items.
insert into lists (owner_user_id, household_id, name, kind, scope)
select h.created_by, h.id, 'Household Grocery', 'grocery', 'household'
from households h
where not exists (
  select 1
  from lists l
  where l.household_id = h.id
    and l.scope = 'household'
    and l.kind = 'grocery'
    and lower(l.name) = 'household grocery'
);

insert into list_items (
  list_id,
  user_id,
  name,
  category,
  quantity,
  unit,
  from_recipe_id,
  source_type,
  created_at
)
select
  l.id,
  g.user_id,
  g.name,
  g.category,
  g.quantity,
  g.unit,
  g.from_recipe_id,
  case when g.from_recipe_id is null then 'manual' else 'planner_recipe' end,
  g.created_at
from grocery_items g
join lists l
  on l.household_id = g.household_id
 and l.scope = 'household'
 and l.kind = 'grocery'
 and lower(l.name) = 'household grocery'
where not exists (
  select 1
  from list_items li
  where li.user_id = g.user_id
    and li.list_id = l.id
    and li.name = g.name
    and coalesce(li.quantity, '') = coalesce(g.quantity, '')
    and coalesce(li.unit, '') = coalesce(g.unit, '')
    and coalesce(li.from_recipe_id::text, '') = coalesce(g.from_recipe_id::text, '')
);

-- 4) Notification persistence scaffolding.
create table if not exists user_device_tokens (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null,
  token text not null unique,
  created_at timestamp with time zone default now(),
  last_seen_at timestamp with time zone default now()
);

create index if not exists user_device_tokens_user_idx on user_device_tokens (user_id);

alter table user_device_tokens enable row level security;

drop policy if exists "user_device_tokens_select_own" on user_device_tokens;
create policy "user_device_tokens_select_own" on user_device_tokens
for select using (user_id = auth.uid());

drop policy if exists "user_device_tokens_write_own" on user_device_tokens;
create policy "user_device_tokens_write_own" on user_device_tokens
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists notification_events (
  id uuid primary key default uuid_generate_v4(),
  event_type text not null,
  household_id uuid references households(id) on delete cascade,
  actor_user_id uuid references profiles(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone default now(),
  processed_at timestamp with time zone
);

create index if not exists notification_events_created_idx on notification_events (created_at desc);
create index if not exists notification_events_type_idx on notification_events (event_type, created_at desc);

alter table notification_events enable row level security;

drop policy if exists "notification_events_household_access" on notification_events;
create policy "notification_events_household_access" on notification_events
for select using (
  (household_id is not null and is_household_member(household_id))
  or actor_user_id = auth.uid()
);

drop policy if exists "notification_events_insert_authenticated" on notification_events;
create policy "notification_events_insert_authenticated" on notification_events
for insert with check (auth.uid() is not null);

create or replace function queue_household_invite_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'invited' then
    insert into notification_events (event_type, household_id, actor_user_id, payload)
    values (
      'household_invite',
      new.household_id,
      auth.uid(),
      jsonb_build_object(
        'household_id', new.household_id,
        'invited_user_id', new.user_id,
        'invited_email', new.invited_email
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists household_members_queue_invite_event on household_members;
create trigger household_members_queue_invite_event
after insert or update on household_members
for each row
execute function queue_household_invite_event();

create or replace function queue_list_item_added_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_household_id uuid;
begin
  select household_id into target_household_id from lists where id = new.list_id;
  if target_household_id is not null then
    insert into notification_events (event_type, household_id, actor_user_id, payload)
    values (
      'list_item_added',
      target_household_id,
      new.user_id,
      jsonb_build_object(
        'list_id', new.list_id,
        'list_item_id', new.id,
        'name', new.name
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists list_items_queue_added_event on list_items;
create trigger list_items_queue_added_event
after insert on list_items
for each row
execute function queue_list_item_added_event();
