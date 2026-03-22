-- Optional per-slot meal prep reminders (local notifications scheduled on each device).
alter table meal_plan_slots
add column if not exists reminder_at timestamptz;

alter table meal_plan_slots
add column if not exists reminder_message text;
