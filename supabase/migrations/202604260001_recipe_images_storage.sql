-- Private recipe image uploads: objects live under {auth.uid()}/...

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'recipe-images',
  'recipe-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic']
)
on conflict (id) do nothing;

-- Authenticated users can upload only into their own top-level folder.
create policy "recipe_images_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'recipe-images'
  and name like auth.uid()::text || '/%'
);

-- Anyone with a public URL can read (bucket is public; paths are unguessable).
create policy "recipe_images_select_public"
on storage.objects
for select
to public
using (bucket_id = 'recipe-images');

-- Owners can replace/delete their own objects.
create policy "recipe_images_update_own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'recipe-images'
  and name like auth.uid()::text || '/%'
)
with check (
  bucket_id = 'recipe-images'
  and name like auth.uid()::text || '/%'
);

create policy "recipe_images_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'recipe-images'
  and name like auth.uid()::text || '/%'
);
