-- Grocery list_items: report uncategorized rows and backfill Produce for common
-- spices/herbs (mirrors `_categoryMap` spice block in
-- lib/features/grocery/data/grocery_repository.dart).
--
-- Run in Supabase SQL editor or psql. Review the report SELECTs before UPDATE.

-- ---------------------------------------------------------------------------
-- 1) Report: most common grocery list rows still in category `other`
-- ---------------------------------------------------------------------------
SELECT
  trim(li.name) AS item_name,
  COUNT(*) AS row_count
FROM public.list_items li
JOIN public.lists l ON l.id = li.list_id
WHERE l.kind = 'grocery'
  AND li.category = 'other'
GROUP BY trim(li.name)
ORDER BY row_count DESC, item_name ASC
LIMIT 200;

-- ---------------------------------------------------------------------------
-- 2) Optional: preview rows that the backfill CASE would change to `produce`
--    (same logic as step 3; run before UPDATE)
-- ---------------------------------------------------------------------------
SELECT
  li.id,
  trim(li.name) AS item_name,
  li.category AS current_category
FROM public.list_items li
JOIN public.lists l ON l.id = li.list_id
WHERE l.kind = 'grocery'
  AND li.category = 'other'
  AND (
    lower(li.name) LIKE '%garam masala%'
    OR lower(li.name) LIKE '%chili powder%'
    OR lower(li.name) LIKE '%curry powder%'
    OR lower(li.name) LIKE '%curry paste%'
    OR lower(li.name) LIKE '%bay leaves%'
    OR lower(li.name) LIKE '%bay leaf%'
    OR lower(li.name) LIKE '%star anise%'
    OR lower(li.name) LIKE '%black pepper%'
    OR lower(li.name) LIKE '%white pepper%'
    OR lower(li.name) LIKE '%peppercorn%'
    OR lower(li.name) LIKE '%pumpkin spice%'
    OR lower(li.name) LIKE '%turmeric%'
    OR lower(li.name) LIKE '%cumin%'
    OR lower(li.name) LIKE '%coriander%'
    OR lower(li.name) LIKE '%paprika%'
    OR lower(li.name) LIKE '%cinnamon%'
    OR lower(li.name) LIKE '%nutmeg%'
    OR lower(li.name) LIKE '%cloves%'
    OR lower(li.name) LIKE '%cayenne%'
    OR lower(li.name) LIKE '%oregano%'
    OR lower(li.name) LIKE '%thyme%'
    OR lower(li.name) LIKE '%rosemary%'
    OR lower(li.name) LIKE '%sage%'
    OR lower(li.name) LIKE '%dill%'
    OR lower(li.name) LIKE '%mint%'
    OR lower(li.name) LIKE '%tarragon%'
    OR lower(li.name) LIKE '%marjoram%'
    OR lower(li.name) LIKE '%chipotle%'
    OR lower(li.name) LIKE '%vanilla%'
    OR lower(li.name) LIKE '%cardamom%'
    OR lower(li.name) LIKE '%allspice%'
    OR lower(li.name) LIKE '%fennel seed%'
    OR lower(li.name) LIKE '%fennel%'
  )
ORDER BY trim(li.name), li.id;

-- ---------------------------------------------------------------------------
-- 3) Backfill: set category to `produce` for matching `other` rows only.
--    Idempotent: safe to re-run; already-`produce` rows are untouched.
-- ---------------------------------------------------------------------------
/*
BEGIN;

UPDATE public.list_items li
SET category = CASE
  WHEN lower(li.name) LIKE '%garam masala%' THEN 'produce'
  WHEN lower(li.name) LIKE '%chili powder%' THEN 'produce'
  WHEN lower(li.name) LIKE '%curry powder%' THEN 'produce'
  WHEN lower(li.name) LIKE '%curry paste%' THEN 'produce'
  WHEN lower(li.name) LIKE '%bay leaves%' THEN 'produce'
  WHEN lower(li.name) LIKE '%bay leaf%' THEN 'produce'
  WHEN lower(li.name) LIKE '%star anise%' THEN 'produce'
  WHEN lower(li.name) LIKE '%black pepper%' THEN 'produce'
  WHEN lower(li.name) LIKE '%white pepper%' THEN 'produce'
  WHEN lower(li.name) LIKE '%peppercorn%' THEN 'produce'
  WHEN lower(li.name) LIKE '%pumpkin spice%' THEN 'produce'
  WHEN lower(li.name) LIKE '%turmeric%' THEN 'produce'
  WHEN lower(li.name) LIKE '%cumin%' THEN 'produce'
  WHEN lower(li.name) LIKE '%coriander%' THEN 'produce'
  WHEN lower(li.name) LIKE '%paprika%' THEN 'produce'
  WHEN lower(li.name) LIKE '%cinnamon%' THEN 'produce'
  WHEN lower(li.name) LIKE '%nutmeg%' THEN 'produce'
  WHEN lower(li.name) LIKE '%cloves%' THEN 'produce'
  WHEN lower(li.name) LIKE '%cayenne%' THEN 'produce'
  WHEN lower(li.name) LIKE '%oregano%' THEN 'produce'
  WHEN lower(li.name) LIKE '%thyme%' THEN 'produce'
  WHEN lower(li.name) LIKE '%rosemary%' THEN 'produce'
  WHEN lower(li.name) LIKE '%sage%' THEN 'produce'
  WHEN lower(li.name) LIKE '%dill%' THEN 'produce'
  WHEN lower(li.name) LIKE '%mint%' THEN 'produce'
  WHEN lower(li.name) LIKE '%tarragon%' THEN 'produce'
  WHEN lower(li.name) LIKE '%marjoram%' THEN 'produce'
  WHEN lower(li.name) LIKE '%chipotle%' THEN 'produce'
  WHEN lower(li.name) LIKE '%vanilla%' THEN 'produce'
  WHEN lower(li.name) LIKE '%cardamom%' THEN 'produce'
  WHEN lower(li.name) LIKE '%allspice%' THEN 'produce'
  WHEN lower(li.name) LIKE '%fennel seed%' THEN 'produce'
  WHEN lower(li.name) LIKE '%fennel%' THEN 'produce'
  ELSE li.category
END
FROM public.lists l
WHERE li.list_id = l.id
  AND l.kind = 'grocery'
  AND li.category = 'other'
  AND (
    lower(li.name) LIKE '%garam masala%'
    OR lower(li.name) LIKE '%chili powder%'
    OR lower(li.name) LIKE '%curry powder%'
    OR lower(li.name) LIKE '%curry paste%'
    OR lower(li.name) LIKE '%bay leaves%'
    OR lower(li.name) LIKE '%bay leaf%'
    OR lower(li.name) LIKE '%star anise%'
    OR lower(li.name) LIKE '%black pepper%'
    OR lower(li.name) LIKE '%white pepper%'
    OR lower(li.name) LIKE '%peppercorn%'
    OR lower(li.name) LIKE '%pumpkin spice%'
    OR lower(li.name) LIKE '%turmeric%'
    OR lower(li.name) LIKE '%cumin%'
    OR lower(li.name) LIKE '%coriander%'
    OR lower(li.name) LIKE '%paprika%'
    OR lower(li.name) LIKE '%cinnamon%'
    OR lower(li.name) LIKE '%nutmeg%'
    OR lower(li.name) LIKE '%cloves%'
    OR lower(li.name) LIKE '%cayenne%'
    OR lower(li.name) LIKE '%oregano%'
    OR lower(li.name) LIKE '%thyme%'
    OR lower(li.name) LIKE '%rosemary%'
    OR lower(li.name) LIKE '%sage%'
    OR lower(li.name) LIKE '%dill%'
    OR lower(li.name) LIKE '%mint%'
    OR lower(li.name) LIKE '%tarragon%'
    OR lower(li.name) LIKE '%marjoram%'
    OR lower(li.name) LIKE '%chipotle%'
    OR lower(li.name) LIKE '%vanilla%'
    OR lower(li.name) LIKE '%cardamom%'
    OR lower(li.name) LIKE '%allspice%'
    OR lower(li.name) LIKE '%fennel seed%'
    OR lower(li.name) LIKE '%fennel%'
  );

COMMIT;
*/
