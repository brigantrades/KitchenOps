-- Diagnostics for missing household push / empty user_device_tokens.
-- Run in Supabase SQL editor or psql (service role sees all rows).

-- 1) Replace with affected auth user ids (no rows in user_device_tokens).
--    If this returns no rows, FK on user_device_tokens.user_id will block inserts.
-- select id, name, created_at
-- from profiles
-- where id in (
--   'a5a9af4f-e985-40a7-802c-e7d29fac72a2'::uuid,
--   '85755d6a-231e-419d-bd34-3efdfc19e70f'::uuid
-- );

-- 2) Tokens registered per user (recent first).
-- select user_id, platform, last_seen_at, left(token, 24) as token_prefix
-- from user_device_tokens
-- where user_id in (
--   'a5a9af4f-e985-40a7-802c-e7d29fac72a2'::uuid,
--   '85755d6a-231e-419d-bd34-3efdfc19e70f'::uuid
-- )
-- order by last_seen_at desc nulls last;

-- 3) Same FCM token row reused across multiple users (RLS can block upsert on account switch).
select token, array_agg(user_id::text order by user_id::text) as user_ids, count(*) as cnt
from user_device_tokens
group by token
having count(*) > 1;

-- 4) Users who appear in active households but have no device token (possible push gaps).
--    Adjust household_id or remove filter to scope.
-- select hm.user_id, p.name
-- from household_members hm
-- join profiles p on p.id = hm.user_id
-- where hm.status = 'active'
--   and hm.household_id = '<household-uuid>'::uuid
--   and not exists (
--     select 1 from user_device_tokens t where t.user_id = hm.user_id
--   );
