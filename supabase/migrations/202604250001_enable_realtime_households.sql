-- Enable Postgres Changes (Realtime) for household rows so planner window (and
-- other shared fields) update for all members without refresh.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'households'
  ) then
    alter publication supabase_realtime add table households;
  end if;
end $$;
