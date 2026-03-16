/// Supabase configuration constants.
/// Peker mot Supabase-prosjektet `ksnnyccthotjbrmgjgdc`.
class SupabaseConfig {
  static const String url = 'https://ksnnyccthotjbrmgjgdc.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8';

  /// Valgfritt: sett denne til selskapet som skal brukes som standard i appen.
  /// Hvis du ikke vet ID-en ennå, kan du la den være null.
  static const String? defaultCompanyId = null;

  // Storage bucket names
  static const String avatarsBucket = 'avatars';
  static const String ticketsBucket = 'tickets';
  static const String documentsBucket = 'documents';
  static const String sjaBucket = 'sja';
  static const String riskBucket = 'risk-assessments';
}
