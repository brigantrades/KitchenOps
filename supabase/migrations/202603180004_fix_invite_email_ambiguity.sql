-- Fix ambiguous "email" reference in invite_household_member.
drop function if exists invite_household_member(text);

create function invite_household_member(email text)
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

  insert into household_members (household_id, user_id, role, status, invited_email)
  values (actor_household, invited_user, 'member', 'active', normalized_email)
  on conflict (household_id, user_id)
  do update set status = 'active', invited_email = excluded.invited_email;

  update profiles
  set household_id = actor_household
  where id = invited_user
    and household_id is null;

  return invited_user;
end;
$$;
