-- Store the inviter's account email on pending invites so invitees can see who added them.

alter table public.household_members
  add column if not exists invited_by_email text;

comment on column public.household_members.invited_by_email is
  'Email of the user who sent the household invite (inviter).';

drop function if exists public.invite_household_member(text);

create function public.invite_household_member(invite_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_household uuid;
  invited_user uuid;
  invited_name text;
  actor_email text;
  normalized_email text := lower(trim(invite_email));
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

  select lower(u.email)
  into actor_email
  from auth.users u
  where u.id = actor
  limit 1;

  select
    u.id,
    coalesce(
      nullif(u.raw_user_meta_data ->> 'name', ''),
      nullif(u.raw_user_meta_data ->> 'full_name', ''),
      split_part(normalized_email, '@', 1)
    )
  into invited_user, invited_name
  from auth.users u
  where lower(u.email) = normalized_email
  limit 1;

  if invited_user is null then
    raise exception 'No account found for that email';
  end if;

  if invited_user = actor then
    raise exception 'Cannot invite yourself';
  end if;

  insert into profiles (id, name)
  values (invited_user, invited_name)
  on conflict (id) do nothing;

  insert into household_members (
    household_id,
    user_id,
    role,
    status,
    invited_email,
    invited_by_email
  )
  values (
    actor_household,
    invited_user,
    'member',
    'invited',
    normalized_email,
    actor_email
  )
  on conflict (household_id, user_id)
  do update set
    invited_email = excluded.invited_email,
    invited_by_email = excluded.invited_by_email,
    status = case
      when household_members.status = 'active' then 'active'
      else 'invited'
    end;

  return invited_user;
end;
$$;

grant execute on function invite_household_member(text) to authenticated;

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
        'invited_email', new.invited_email,
        'invited_by_email', new.invited_by_email
      )
    );
  end if;
  return new;
end;
$$;
