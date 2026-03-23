-- Postgres Changes (Realtime) for recipes so household members see edits without refresh.
-- REPLICA IDENTITY FULL helps DELETE events satisfy RLS when evaluating old rows.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'recipes'
  ) then
    alter publication supabase_realtime add table recipes;
  end if;
end $$;

alter table public.recipes replica identity full;
