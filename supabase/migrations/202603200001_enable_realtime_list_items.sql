-- Enable Postgres Changes (Realtime) for grocery rows so household members see
-- inserts/updates/deletes without refreshing the app.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'list_items'
  ) then
    alter publication supabase_realtime add table list_items;
  end if;
end $$;
