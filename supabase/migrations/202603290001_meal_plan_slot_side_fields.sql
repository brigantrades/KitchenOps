-- Optional side for planner meal slots (parallel to main meal + sauce).
alter table meal_plan_slots
add column if not exists side_recipe_id uuid references recipes(id) on delete set null;

alter table meal_plan_slots
add column if not exists side_text text;
