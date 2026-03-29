-- create_household_with_member omitted planner columns; NOT NULL without relying on table defaults.
create or replace function create_household_with_member(name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  household_uuid uuid;
  actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  insert into households (name, created_by, planner_start_day, planner_day_count)
  values (
    coalesce(nullif(trim(name), ''), 'My Household'),
    actor,
    0,
    7
  )
  returning id into household_uuid;

  insert into household_members (household_id, user_id, role, status)
  values (household_uuid, actor, 'owner', 'active')
  on conflict (household_id, user_id) do nothing;

  update profiles
  set household_id = household_uuid
  where id = actor;

  return household_uuid;
end;
$$;
