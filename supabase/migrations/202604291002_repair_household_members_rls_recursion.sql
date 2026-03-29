-- Restore non-recursive household RLS if 202603180002 was replayed without this fix.
-- (Policies that subquery household_members from household_members cause 42P17.)

create or replace function is_household_member(
  target_household_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = target_user_id
      and hm.status = 'active'
  );
$$;

grant execute on function is_household_member(uuid, uuid) to authenticated;

drop policy if exists "households_select_member" on households;
create policy "households_select_member" on households
for select using (
  exists (
    select 1
    from household_members hm
    where hm.household_id = households.id
      and hm.user_id = auth.uid()
      and hm.status in ('active', 'invited')
  )
);

drop policy if exists "households_update_member" on households;
create policy "households_update_member" on households
for update
using (is_household_member(households.id))
with check (is_household_member(households.id));

drop policy if exists "household_members_select_member" on household_members;
create policy "household_members_select_member" on household_members
for select using (
  is_household_member(household_members.household_id)
  or household_members.user_id = auth.uid()
);

drop policy if exists "household_members_insert_member" on household_members;
create policy "household_members_insert_member" on household_members
for insert with check (is_household_member(household_members.household_id));

drop policy if exists "household_members_update_member" on household_members;
create policy "household_members_update_member" on household_members
for update
using (is_household_member(household_members.household_id))
with check (is_household_member(household_members.household_id));

drop policy if exists "recipes_select_visibility" on recipes;
create policy "recipes_select_visibility" on recipes
for select using (
  (visibility = 'public')
  or (visibility = 'personal' and user_id = auth.uid())
  or (visibility = 'household' and is_household_member(recipes.household_id))
);

drop policy if exists "recipes_insert_visibility" on recipes;
create policy "recipes_insert_visibility" on recipes
for insert with check (
  (visibility = 'personal' and user_id = auth.uid())
  or (
    visibility = 'household'
    and user_id = auth.uid()
    and is_household_member(recipes.household_id)
  )
  or (visibility = 'public' and user_id = auth.uid())
);

drop policy if exists "recipes_update_visibility" on recipes;
create policy "recipes_update_visibility" on recipes
for update
using (
  (visibility = 'personal' and user_id = auth.uid())
  or (visibility = 'household' and is_household_member(recipes.household_id))
)
with check (
  (visibility = 'personal' and user_id = auth.uid())
  or (visibility = 'household' and is_household_member(recipes.household_id))
  or (visibility = 'public' and user_id = auth.uid())
);

drop policy if exists "recipes_delete_visibility" on recipes;
create policy "recipes_delete_visibility" on recipes
for delete using (
  (visibility = 'personal' and user_id = auth.uid())
  or (visibility = 'household' and is_household_member(recipes.household_id))
);

drop policy if exists "slots_select_household" on meal_plan_slots;
create policy "slots_select_household" on meal_plan_slots
for select using (is_household_member(meal_plan_slots.household_id));

drop policy if exists "slots_write_household" on meal_plan_slots;
create policy "slots_write_household" on meal_plan_slots
for all
using (is_household_member(meal_plan_slots.household_id))
with check (is_household_member(meal_plan_slots.household_id));

drop policy if exists "grocery_select_household" on grocery_items;
create policy "grocery_select_household" on grocery_items
for select using (is_household_member(grocery_items.household_id));

drop policy if exists "grocery_write_household" on grocery_items;
create policy "grocery_write_household" on grocery_items
for all
using (is_household_member(grocery_items.household_id))
with check (is_household_member(grocery_items.household_id));
