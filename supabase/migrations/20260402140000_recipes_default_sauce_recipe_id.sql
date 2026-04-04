-- Optional default sauce/icing recipe linked from a main recipe (for planner pre-fill and grocery).
alter table public.recipes
  add column if not exists default_sauce_recipe_id uuid references public.recipes(id) on delete set null;

create index if not exists recipes_default_sauce_recipe_id_idx
  on public.recipes (default_sauce_recipe_id)
  where default_sauce_recipe_id is not null;
