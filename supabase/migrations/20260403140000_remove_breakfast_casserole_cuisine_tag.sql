-- Remove "Breakfast Casserole" / "breakfast casserole" from recipe cuisine_tags
-- (case-insensitive match on the whole tag).

update recipes
set cuisine_tags = coalesce(
  array(
    select tag
    from unnest(coalesce(cuisine_tags, '{}'::text[])) as q(tag)
    where lower(trim(tag)) <> 'breakfast casserole'
  ),
  '{}'::text[]
)
where cuisine_tags is not null
  and exists (
    select 1
    from unnest(cuisine_tags) as u(tag)
    where lower(trim(tag)) = 'breakfast casserole'
  );
