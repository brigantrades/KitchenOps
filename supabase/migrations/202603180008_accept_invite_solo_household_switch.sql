-- Allow accepting an invite when the user is only in a solo household
-- (common when a personal household was auto-created before joining another).

create or replace function accept_household_invite_with_switch(household_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  current_household uuid;
  current_active_count integer := 0;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from household_members hm
    where hm.household_id = household_uuid
      and hm.user_id = actor
      and hm.status = 'invited'
  ) then
    raise exception 'Invite not found';
  end if;

  -- Ensure profile row exists before switching household pointer.
  insert into profiles (id, name)
  values (actor, 'KitchenOps User')
  on conflict (id) do nothing;

  select p.household_id
  into current_household
  from profiles p
  where p.id = actor;

  if current_household is not null and current_household <> household_uuid then
    select count(*)
    into current_active_count
    from household_members hm
    where hm.household_id = current_household
      and hm.status = 'active';

    -- Only permit automatic switching when the current household is solo.
    if current_active_count > 1 then
      raise exception 'You are already in another household';
    end if;
  end if;

  update household_members
  set status = 'active'
  where household_id = household_uuid
    and user_id = actor;

  update profiles
  set household_id = household_uuid
  where id = actor;
end;
$$;

grant execute on function accept_household_invite_with_switch(uuid) to authenticated;
