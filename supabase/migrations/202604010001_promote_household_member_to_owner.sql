-- Allow household owners to promote active members to co-owner (same privileges).

create or replace function promote_household_member_to_owner(member_user_id uuid)
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
    raise exception 'Only household owners can promote members';
  end if;

  if member_user_id = actor then
    raise exception 'You are already an owner';
  end if;

  if not exists (
    select 1
    from household_members hm
    where hm.household_id = actor_household
      and hm.user_id = member_user_id
      and hm.status = 'active'
      and hm.role = 'member'
  ) then
    raise exception 'Active member not found or already an owner';
  end if;

  update household_members
  set role = 'owner'
  where household_id = actor_household
    and user_id = member_user_id
    and status = 'active';
end;
$$;

grant execute on function promote_household_member_to_owner(uuid) to authenticated;
