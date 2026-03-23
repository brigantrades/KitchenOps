-- Map legacy meal-time labels to canonical kinds (UI shows Meal 1… / Snack 1… by order).
update meal_plan_slots
set meal_type = 'meal'
where lower(meal_type) in (
  'breakfast',
  'brunch',
  'lunch',
  'dinner',
  'supper',
  'dessert'
);
