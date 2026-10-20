import 'work_steps_health_auth_result.dart';

/// iOS/Android: HealthKit / Health Connect er fjernet fra App Store / Play-bygg
/// (Apple 2.5.1 / Play health declarations). Skritt kan komme tilbake senere
/// uten HealthKit-rammeverket i iOS-binæren.
Future<bool> isSupported() async => false;

Future<WorkStepsHealthAuthResult> requestAuthorization() async {
  return const WorkStepsHealthAuthResult(
    ok: false,
    message:
        'Skritt på jobb er midlertidig utilgjengelig i denne app-versjonen.',
  );
}

Future<void> installHealthConnect() async {}

Future<int?> stepsToday() async => null;
