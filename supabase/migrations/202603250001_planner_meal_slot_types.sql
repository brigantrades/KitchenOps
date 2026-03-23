-- Normalize legacy planner slot kinds to "meal" (display is order-based: Meal 1, Meal 2, …).
update meal_plan_slots
set meal_type = 'meal'
where lower(meal_type) in ('entree', 'side', 'sauce');
