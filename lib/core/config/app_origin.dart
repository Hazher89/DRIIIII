/// Production URL for auth redirects and e-postlenker.
const String kProductionOrigin = 'https://driftpro.no';

/// Brukes for OAuth og magic links — følger localhost i lokal utvikling.
String get appAuthRedirectOrigin {
  final origin = Uri.base.origin.trim();
  if (origin.isEmpty) return kProductionOrigin;
  if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
    return origin;
  }
  return kProductionOrigin;
}
