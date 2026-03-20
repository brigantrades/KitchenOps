-- Per-user preferred order of grocery lists (private vs household), for UI defaults and dropdown ordering.
alter table profiles
add column if not exists grocery_list_order jsonb not null default '{}'::jsonb;
