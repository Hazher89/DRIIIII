/// Resultat av native helse-tilgang (etter samtykke i DriftPro).
class WorkStepsHealthAuthResult {
  const WorkStepsHealthAuthResult({
    required this.ok,
    this.message,
    this.needsHealthConnectInstall = false,
    this.stepsProbe,
  });

  final bool ok;
  final String? message;
  final bool needsHealthConnectInstall;

  /// Dagens skritt hvis lesing fungerte (også 0).
  final int? stepsProbe;
}
