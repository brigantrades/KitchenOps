-- Remove legacy placeholder profile names so users must set first name in onboarding.
update profiles
set name = null
where trim(coalesce(name, '')) = 'Leckerly User';
