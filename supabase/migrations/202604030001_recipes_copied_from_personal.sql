-- Household copies of a personal recipe: stable link for idempotent share and precise delete.
-- Partial unique index only applies when the column is set (legacy rows remain NULL).

alter table recipes
add column if not exists copied_from_personal_recipe_id uuid references recipes(id) on delete set null;

create unique index if not exists recipes_one_household_copy_per_personal_source
on recipes (user_id, copied_from_personal_recipe_id)
where visibility = 'household' and copied_from_personal_recipe_id is not null;
