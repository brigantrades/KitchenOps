-- Merge duplicate public discover rows that share the same recipe URL (different
-- api_id / cuisine_tags from separate import buckets). Keeps the lexicographically
-- smallest recipe id per group, unions cuisine_tags, repoints FKs, deletes extras.
--
-- Safe for: is_public recipes with non-empty source_url, grouped by (user_id, normalized url).
-- Applied inside Supabase's migration transaction (no explicit BEGIN/COMMIT).

create temporary table _recipe_dedupe_merge (
  loser_id uuid primary key,
  winner_id uuid not null
) on commit drop;

with dup_groups as (
  select
    user_id,
    lower(
      regexp_replace(
        regexp_replace(btrim(source_url), '^http://', 'https://'),
        '/$',
        ''
      )
    ) as url_key,
    array_agg(id order by id::text) as ids
  from recipes
  where coalesce(is_public, false) = true
    and source_url is not null
    and length(btrim(source_url)) > 0
  group by user_id, url_key
  having count(*) > 1
),
canonical as (
  select ids[1] as winner_id, ids as all_ids
  from dup_groups
)
insert into _recipe_dedupe_merge (loser_id, winner_id)
select u.mid, c.winner_id
from canonical c
cross join lateral unnest(c.all_ids) as u(mid)
where u.mid <> c.winner_id;

-- Union cuisine_tags onto the surviving row (distinct, sorted).
update recipes r
set cuisine_tags = coalesce(sub.tags, '{}'::text[])
from (
  select
    c.winner_id,
    (
      select array_agg(distinct t order by t)
      from recipes r2,
      lateral unnest(coalesce(r2.cuisine_tags, '{}'::text[])) as u(t)
      where r2.id = any (c.all_ids)
    ) as tags
  from (
    select ids[1] as winner_id, ids as all_ids
    from (
      select
        user_id,
        lower(
          regexp_replace(
            regexp_replace(btrim(source_url), '^http://', 'https://'),
            '/$',
            ''
          )
        ) as url_key,
        array_agg(id order by id::text) as ids
      from recipes
      where coalesce(is_public, false) = true
        and source_url is not null
        and length(btrim(source_url)) > 0
      group by user_id, url_key
      having count(*) > 1
    ) g
  ) c
) sub
where r.id = sub.winner_id;

update meal_plan_slots s
set recipe_id = m.winner_id
from _recipe_dedupe_merge m
where s.recipe_id = m.loser_id;

update meal_plan_slots s
set side_recipe_id = m.winner_id
from _recipe_dedupe_merge m
where s.side_recipe_id = m.loser_id;

update meal_plan_slots s
set sauce_recipe_id = m.winner_id
from _recipe_dedupe_merge m
where s.sauce_recipe_id = m.loser_id;

update list_items li
set from_recipe_id = m.winner_id
from _recipe_dedupe_merge m
where li.from_recipe_id = m.loser_id;

update recipes r
set copied_from_personal_recipe_id = m.winner_id
from _recipe_dedupe_merge m
where r.copied_from_personal_recipe_id = m.loser_id;

-- Legacy installs may still have grocery_items with from_recipe_id (before delete).
do $do$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'grocery_items'
  ) then
    update grocery_items gi
    set from_recipe_id = m.winner_id
    from _recipe_dedupe_merge m
    where gi.from_recipe_id = m.loser_id;
  end if;
end
$do$;

delete from recipes d
using _recipe_dedupe_merge m
where d.id = m.loser_id;
