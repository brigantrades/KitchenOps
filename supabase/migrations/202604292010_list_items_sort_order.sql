-- Manual order for items within a grocery list (sort_order) + RPC to batch-update after drag.

alter table public.list_items
  add column if not exists sort_order integer not null default 0;

with ranked as (
  select
    id,
    row_number() over (partition by list_id order by created_at asc) as rn
  from public.list_items
)
update public.list_items li
set sort_order = ranked.rn
from ranked
where li.id = ranked.id;

create index if not exists list_items_list_sort_idx
  on public.list_items (list_id, sort_order);

-- New rows append after existing items (concurrent inserts may rarely share a sort_order).
create or replace function public.list_items_assign_sort_order()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.sort_order :=
    coalesce(
      (select max(li.sort_order) + 1 from public.list_items li where li.list_id = new.list_id),
      0
    );
  return new;
end;
$$;

drop trigger if exists list_items_assign_sort_order_trigger on public.list_items;
create trigger list_items_assign_sort_order_trigger
before insert on public.list_items
for each row
execute function public.list_items_assign_sort_order();

create or replace function public.reorder_list_items(p_list_id uuid, p_item_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  i int := 0;
  v_id uuid;
begin
  foreach v_id in array p_item_ids
  loop
    update public.list_items
    set sort_order = i
    where id = v_id and list_id = p_list_id;
    i := i + 1;
  end loop;
end;
$$;

grant execute on function public.reorder_list_items(uuid, uuid[]) to authenticated;
