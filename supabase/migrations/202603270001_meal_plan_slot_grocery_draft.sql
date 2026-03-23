-- Persist custom ingredient lines for planner slots (e.g. text-only meals) for the add-to-grocery sheet.
alter table meal_plan_slots
add column if not exists grocery_draft_lines jsonb not null default '[]'::jsonb;
