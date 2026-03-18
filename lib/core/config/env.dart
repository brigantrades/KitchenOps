class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const spoonacularApiKey = String.fromEnvironment('SPOONACULAR_API_KEY');
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const firebaseEnabled = bool.fromEnvironment('FIREBASE_ENABLED', defaultValue: false);

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get hasSpoonacular => spoonacularApiKey.isNotEmpty;
  static bool get hasGemini => geminiApiKey.isNotEmpty;
}
