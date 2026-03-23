-- Custom planner window: start weekday (0=Mon..6=Sun) + day count (1–14).
-- Household default; profile may use household or set an explicit override.

alter table households
add column if not exists planner_start_day int,
add column if not exists planner_day_count int;

update households
set planner_start_day = coalesce(planner_start_day, 0),
    planner_day_count = coalesce(planner_day_count, 7);

alter table households
alter column planner_start_day set not null,
alter column planner_day_count set not null;

alter table households
drop constraint if exists households_planner_start_day_check;

alter table households
add constraint households_planner_start_day_check
check (planner_start_day >= 0 and planner_start_day <= 6);

alter table households
drop constraint if exists households_planner_day_count_check;

alter table households
add constraint households_planner_day_count_check
check (planner_day_count >= 1 and planner_day_count <= 14);

alter table profiles
add column if not exists planner_use_household_default boolean default true,
add column if not exists planner_start_day int,
add column if not exists planner_day_count int;

update profiles
set planner_use_household_default = coalesce(planner_use_household_default, true);

alter table profiles
alter column planner_use_household_default set not null,
alter column planner_use_household_default set default true;

-- Users who chose Mon–Mon (8 days) keep an explicit override; others follow household default.
update profiles
set planner_use_household_default = false,
    planner_start_day = 0,
    planner_day_count = 8
where planner_week_view = 'mon_mon_8day';

alter table profiles
drop constraint if exists profiles_planner_start_day_check;

alter table profiles
add constraint profiles_planner_start_day_check
check (planner_start_day is null or (planner_start_day >= 0 and planner_start_day <= 6));

alter table profiles
drop constraint if exists profiles_planner_day_count_check;

alter table profiles
add constraint profiles_planner_day_count_check
check (
  planner_day_count is null
  or (planner_day_count >= 1 and planner_day_count <= 14)
);

alter table profiles
drop constraint if exists profiles_planner_override_consistent;

alter table profiles
add constraint profiles_planner_override_consistent
check (
  planner_use_household_default = true
  or (
    planner_start_day is not null
    and planner_day_count is not null
  )
);
