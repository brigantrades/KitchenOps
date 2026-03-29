-- Inserts that omit planner columns (e.g. create_household_with_member) must not violate NOT NULL.
alter table households
  alter column planner_start_day set default 0,
  alter column planner_day_count set default 7;
