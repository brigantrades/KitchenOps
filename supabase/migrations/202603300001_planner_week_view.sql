-- Per-user planner calendar window (Mon–Sun vs Mon–Mon 8-day).
alter table profiles
add column if not exists planner_week_view text not null default 'mon_sun';

alter table profiles
drop constraint if exists profiles_planner_week_view_check;

alter table profiles
add constraint profiles_planner_week_view_check
check (planner_week_view in ('mon_sun', 'mon_mon_8day'));
