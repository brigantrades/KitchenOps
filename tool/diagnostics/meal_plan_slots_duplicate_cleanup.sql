-- Diagnose duplicate meal_plan_slots rows per household slot position.
-- Expected: 0 rows (unique index meal_plan_slots_household_week_day_order_uidx).
--
-- Run in Supabase SQL editor or psql. Review SELECT before DELETE.

-- 1) Find groups with more than one row for the same logical slot
SELECT
  household_id,
  week_start,
  day_of_week,
  slot_order,
  COUNT(*) AS row_count,
  ARRAY_AGG(id ORDER BY created_at) AS ids
FROM public.meal_plan_slots
GROUP BY household_id, week_start, day_of_week, slot_order
HAVING COUNT(*) > 1;

-- 2) Optional: delete duplicates, keeping the "best" row per group.
--    Priority: has recipe_id > has meal_text > earliest created_at.
--    Run inside a transaction; uncomment when ready.

/*
BEGIN;

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY household_id, week_start, day_of_week, slot_order
      ORDER BY
        (recipe_id IS NOT NULL) DESC,
        (NULLIF(TRIM(COALESCE(meal_text, '')), '') IS NOT NULL) DESC,
        created_at ASC NULLS LAST,
        id ASC
    ) AS rn
  FROM public.meal_plan_slots
)
DELETE FROM public.meal_plan_slots m
USING ranked r
WHERE m.id = r.id AND r.rn > 1;

COMMIT;
*/
