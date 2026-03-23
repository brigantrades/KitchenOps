-- Clean up existing duplicate household recipe copies.
-- Strategy:
-- 1) Ensure copied_from_personal_recipe_id exists.
-- 2) Temporarily drop the partial unique index (if present).
-- 3) Backfill copied_from_personal_recipe_id for legacy household rows by
--    matching same user + same title to a personal recipe.
-- 4) Remove duplicate household rows per (user_id, copied_from_personal_recipe_id),
--    keeping the most recently created row.
-- 5) Recreate the partial unique index to prevent future duplicates.

alter table recipes
add column if not exists copied_from_personal_recipe_id uuid references recipes(id) on delete set null;

drop index if exists recipes_one_household_copy_per_personal_source;

with matched_personal as (
  select
    h.id as household_recipe_id,
    (
      select p.id
      from recipes p
      where p.user_id = h.user_id
        and p.visibility = 'personal'
        and p.title = h.title
      order by p.created_at desc
      limit 1
    ) as personal_recipe_id
  from recipes h
  where h.visibility = 'household'
    and h.copied_from_personal_recipe_id is null
)
update recipes h
set copied_from_personal_recipe_id = m.personal_recipe_id
from matched_personal m
where h.id = m.household_recipe_id
  and m.personal_recipe_id is not null;

with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, copied_from_personal_recipe_id
      order by created_at desc, id desc
    ) as rn
  from recipes
  where visibility = 'household'
    and copied_from_personal_recipe_id is not null
)
delete from recipes r
using ranked d
where r.id = d.id
  and d.rn > 1;

create unique index if not exists recipes_one_household_copy_per_personal_source
on recipes (user_id, copied_from_personal_recipe_id)
where visibility = 'household' and copied_from_personal_recipe_id is not null;
