-- Parameter name "email" can be ambiguous with auth.users.email inside the
-- function body in some PostgreSQL/Supabase versions. Rename to invite_email.
-- CREATE OR REPLACE cannot rename parameters (42P13); drop then create.
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

grant execute on function invite_household_member(text) to authenticated;
