-- Household member management:
-- - Owners can remove non-owner members from their active household.
-- - Active non-owner members can leave their household.

create or replace function remove_household_member(member_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  actor_role text;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  select p.household_id
  into actor_household
  from profiles p
  where p.id = actor;

  if actor_household is null then
    raise exception 'No active household';
  end if;

  select hm.role
  into actor_role
  from household_members hm
  where hm.household_id = actor_household
    and hm.user_id = actor
    and hm.status = 'active'
  limit 1;

  if actor_role is distinct from 'owner' then
    raise exception 'Only household owners can remove members';
  end if;

  if member_user_id = actor then
    raise exception 'Use leave_household to remove yourself';
  end if;

  if exists (
    select 1
    from household_members hm
    where hm.household_id = actor_household
      and hm.user_id = member_user_id
      and hm.role = 'owner'
  ) then
    raise exception 'Cannot remove another owner';
  end if;

  delete from household_members hm
  where hm.household_id = actor_household
    and hm.user_id = member_user_id;

  update profiles p
  set household_id = null
  where p.id = member_user_id
    and p.household_id = actor_household;
end;
$$;

create or replace function leave_household()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  actor_role text;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  select p.household_id
  into actor_household
  from profiles p
  where p.id = actor;

  if actor_household is null then
    raise exception 'No active household';
  end if;

  select hm.role
  into actor_role
  from household_members hm
  where hm.household_id = actor_household
    and hm.user_id = actor
    and hm.status = 'active'
  limit 1;

  if actor_role is null then
    raise exception 'Active membership not found';
  end if;

  if actor_role = 'owner' then
    raise exception 'Owner cannot leave household';
  end if;

  delete from household_members hm
  where hm.household_id = actor_household
    and hm.user_id = actor;

  update profiles p
  set household_id = null
  where p.id = actor
    and p.household_id = actor_household;
end;
$$;

grant execute on function remove_household_member(uuid) to authenticated;
grant execute on function leave_household() to authenticated;
