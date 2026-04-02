/// Canonical dietary tags for profile and Discover filtering.
/// Slugs match [Profile.dietaryRestrictions] and filter logic (substring match on title + tags).
enum DietaryOption {
  vegetarian('Vegetarian'),
  vegan('Vegan'),
  glutenFree('Gluten-Free'),
  dairyFree('Dairy-Free'),
  keto('Keto'),
  paleo('Paleo'),
  whole30('Whole30'),
  pescatarian('Pescatarian'),
  nutFree('Nut-Free');

  const DietaryOption(this.label);
  final String label;

  /// Lowercase tag stored in DB and used in Discover filters, e.g. `gluten-free`, `whole30`.
  String get slug => name
      .replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '-${m[0]!.toLowerCase()}',
      )
      .replaceFirst(RegExp('^-'), '');
}
