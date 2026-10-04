class AppEnvironment {
  static const String _defaultSupabaseUrl =
      'https://xmhbrnkukhmzizkiyyhg.supabase.co';
  static const String _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtaGJybmt1a2hteml6a2l5eWhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg3MjgyMTIsImV4cCI6MjA3NDMwNDIxMn0.hEz_6Sd4LalpqAiMBWfzADURX3UGKX9UPZfBch6M6vU';

  static const String _supabaseUrlFromEnv =
      String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKeyFromEnv =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl => _supabaseUrlFromEnv.isNotEmpty
      ? _supabaseUrlFromEnv
      : _defaultSupabaseUrl;

  static String get supabaseAnonKey => _supabaseAnonKeyFromEnv.isNotEmpty
      ? _supabaseAnonKeyFromEnv
      : _defaultSupabaseAnonKey;

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get demoMode => !supabaseConfigured;
}
