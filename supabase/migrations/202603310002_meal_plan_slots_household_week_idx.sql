-- Speed up planner queries: filter by household + ISO week (listSlots, realtime client filters).
create index if not exists meal_plan_slots_household_week_idx
  on public.meal_plan_slots (household_id, week_start);
