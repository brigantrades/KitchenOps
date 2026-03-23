-- Reliable Realtime DELETE delivery with RLS: include full old row in replication.
alter table public.list_items replica identity full;
