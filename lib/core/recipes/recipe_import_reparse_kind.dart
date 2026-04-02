/// How [ImportRecipePreviewScreen] re-parses AI import source text.
enum RecipeImportReparseKind {
  /// Caption / share text (Instagram and similar).
  instagramCaption,

  /// Fetched web page plain text (recipe sites, blogs).
  webPage,
}
