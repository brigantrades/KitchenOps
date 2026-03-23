-- Per-member assignment for planner slots.
create table if not exists meal_plan_slot_members (
  slot_id uuid not null references meal_plan_slots(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamp with time zone default now(),
  primary key (slot_id, user_id)
);

create index if not exists meal_plan_slot_members_slot_idx
  on meal_plan_slot_members (slot_id);

create index if not exists meal_plan_slot_members_user_idx
  on meal_plan_slot_members (user_id);

alter table meal_plan_slot_members enable row level security;

drop policy if exists "slot_members_select_household" on meal_plan_slot_members;
create policy "slot_members_select_household" on meal_plan_slot_members
for select using (
  exists (
    select 1
    from meal_plan_slots s
    join household_members hm on hm.household_id = s.household_id
    where s.id = meal_plan_slot_members.slot_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "slot_members_insert_household" on meal_plan_slot_members;
create policy "slot_members_insert_household" on meal_plan_slot_members
for insert with check (
  exists (
    select 1
    from meal_plan_slots s
    join household_members hm on hm.household_id = s.household_id
    where s.id = meal_plan_slot_members.slot_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

drop policy if exists "slot_members_delete_household" on meal_plan_slot_members;
create policy "slot_members_delete_household" on meal_plan_slot_members
for delete using (
  exists (
    select 1
    from meal_plan_slots s
    join household_members hm on hm.household_id = s.household_id
    where s.id = meal_plan_slot_members.slot_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  )
);

-- Backfill legacy slots as shared: assign all active household members.
insert into meal_plan_slot_members (slot_id, user_id)
select s.id, hm.user_id
from meal_plan_slots s
join household_members hm on hm.household_id = s.household_id
where hm.status = 'active'
on conflict (slot_id, user_id) do nothing;
