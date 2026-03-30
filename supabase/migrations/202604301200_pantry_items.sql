-- Household pantry inventory (stock levels for meal-plan vs shopping deficits).

create table if not exists pantry_items (
  id uuid primary key default uuid_generate_v4(),
  household_id uuid not null references households(id) on delete cascade,
  name text not null,
  category text not null default 'other',
  current_quantity double precision not null default 0,
  unit text not null default 'g',
  buffer_threshold double precision,
  fdc_id integer,
  last_audit_at timestamp with time zone,
  sort_order integer not null default 0,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists pantry_items_household_idx
  on pantry_items (household_id, sort_order, created_at);

comment on table pantry_items is 'Per-household kitchen stock; quantities use [unit] with normalized math on the client (g, ml, count, etc.).';

alter table pantry_items enable row level security;

drop policy if exists "pantry_items_select" on pantry_items;
create policy "pantry_items_select" on pantry_items
for select using (is_household_member(household_id));

drop policy if exists "pantry_items_insert" on pantry_items;
create policy "pantry_items_insert" on pantry_items
for insert with check (
  is_household_member(household_id)
  and (created_by is null or created_by = auth.uid())
);

drop policy if exists "pantry_items_update" on pantry_items;
create policy "pantry_items_update" on pantry_items
for update using (is_household_member(household_id))
with check (is_household_member(household_id));

drop policy if exists "pantry_items_delete" on pantry_items;
create policy "pantry_items_delete" on pantry_items
for delete using (is_household_member(household_id));

create or replace function set_pantry_items_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists pantry_items_set_updated_at on pantry_items;
create trigger pantry_items_set_updated_at
before update on pantry_items
for each row
execute function set_pantry_items_updated_at();

-- Realtime for shared pantry edits.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pantry_items'
  ) then
    alter publication supabase_realtime add table pantry_items;
  end if;
end $$;

