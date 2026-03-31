-- Shareable recipe snapshots for universal links (https://leckerly.app/r/<id>).

create table if not exists recipe_shares (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamp with time zone not null default now(),
  created_by uuid not null references profiles(id) on delete cascade,
  source_recipe_id uuid references recipes(id) on delete set null,
  payload jsonb not null
);

create index if not exists recipe_shares_created_by_idx
  on recipe_shares (created_by, created_at desc);

comment on table recipe_shares is 'Recipe snapshots created for sharing via universal links; payload is a Recipe JSON without ownership fields.';

alter table recipe_shares enable row level security;

drop policy if exists "recipe_shares_insert" on recipe_shares;
create policy "recipe_shares_insert" on recipe_shares
for insert with check (
  auth.uid() is not null
  and created_by = auth.uid()
);

drop policy if exists "recipe_shares_select" on recipe_shares;
create policy "recipe_shares_select" on recipe_shares
for select using (auth.uid() is not null);

