alter table meal_plan_slots
add column if not exists slot_order int default 0 not null;

-- Replace strict meal_type uniqueness with slot ordering uniqueness so users can add custom slots.
alter table meal_plan_slots
drop constraint if exists meal_plan_slots_user_id_week_start_day_of_week_meal_type_key;

create unique index if not exists meal_plan_slots_user_week_day_order_uidx
on meal_plan_slots (user_id, week_start, day_of_week, slot_order);
