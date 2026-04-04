-- Sauce/icing content stored on the main recipe (no separate recipe row).
alter table public.recipes
  add column if not exists embedded_sauce jsonb;

comment on column public.recipes.embedded_sauce is
  'Optional sauce/icing: { title?, ingredients: [...], instructions: [...] } — same servings as main.';
