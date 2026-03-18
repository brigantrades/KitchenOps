-- Support in-app household invite acceptance/rejection for existing users.

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
  normalized_email text := lower(trim($1));
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

  select u.id
  into invited_user
  from auth.users u
  where lower(u.email) = normalized_email
  limit 1;

  if invited_user is null then
    raise exception 'No account found for that email';
  end if;

  if invited_user = actor then
    raise exception 'Cannot invite yourself';
  end if;

  insert into household_members (household_id, user_id, role, status, invited_email)
  values (actor_household, invited_user, 'member', 'invited', normalized_email)
  on conflict (household_id, user_id)
  do update set
    invited_email = excluded.invited_email,
    status = case
      when household_members.status = 'active' then 'active'
      else 'invited'
    end;

  return invited_user;
end;
$$;

create or replace function accept_household_invite(household_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  current_household uuid;
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

  select p.household_id
  into current_household
  from profiles p
  where p.id = actor;

  if current_household is not null and current_household <> household_uuid then
    raise exception 'You are already in another household';
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

create or replace function reject_household_invite(household_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  delete from household_members
  where household_id = household_uuid
    and user_id = actor
    and status = 'invited';
end;
$$;

grant execute on function accept_household_invite(uuid) to authenticated;
grant execute on function reject_household_invite(uuid) to authenticated;

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

drop policy if exists "household_members_select_member" on household_members;
create policy "household_members_select_member" on household_members
for select using (
  is_household_member(household_members.household_id)
  or household_members.user_id = auth.uid()
);
