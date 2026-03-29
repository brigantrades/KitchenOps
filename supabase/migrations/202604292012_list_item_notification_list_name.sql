-- Include grocery list name in list_item_added notification payload for FCM body text.

create or replace function public.queue_list_item_added_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_household_id uuid;
  target_list_name text;
begin
  select l.household_id, l.name
  into target_household_id, target_list_name
  from public.lists l
  where l.id = new.list_id;

  if target_household_id is not null then
    insert into public.notification_events (event_type, household_id, actor_user_id, payload)
    values (
      'list_item_added',
      target_household_id,
      new.user_id,
      jsonb_build_object(
        'list_id', new.list_id,
        'list_item_id', new.id,
        'name', new.name,
        'list_name', coalesce(target_list_name, '')
      )
    );
  end if;
  return new;
end;
$$;
