alter table profiles
add column if not exists household_servings int default 2;

alter table profiles
drop constraint if exists profiles_household_servings_check;

alter table profiles
add constraint profiles_household_servings_check
check (household_servings is null or (household_servings >= 1 and household_servings <= 12));
