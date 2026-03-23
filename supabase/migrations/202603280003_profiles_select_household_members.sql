-- Allow household members to read profile rows (for displaying member names).
drop policy if exists "profiles_select_own" on profiles;
drop policy if exists "profiles_select_household" on profiles;

create policy "profiles_select_household" on profiles
for select using (
  auth.uid() = id
  or exists (
    select 1
    from household_members me
    join household_members other
      on other.household_id = me.household_id
    where me.user_id = auth.uid()
      and me.status = 'active'
      and other.user_id = profiles.id
      and other.status = 'active'
  )
);
