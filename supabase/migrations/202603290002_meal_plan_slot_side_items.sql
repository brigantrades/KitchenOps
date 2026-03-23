-- Allow multiple optional sides per planner slot.
alter table meal_plan_slots
add column if not exists side_items jsonb not null default '[]'::jsonb;

-- Backfill existing single-side values into side_items.
update meal_plan_slots
set side_items = jsonb_build_array(
  jsonb_build_object(
    'recipe_id', side_recipe_id,
    'text', side_text
  )
)
where coalesce(jsonb_array_length(side_items), 0) = 0
  and (side_recipe_id is not null or nullif(trim(side_text), '') is not null);
