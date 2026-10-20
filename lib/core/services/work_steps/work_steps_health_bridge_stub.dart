import 'work_steps_health_auth_result.dart';

export 'work_steps_health_auth_result.dart';

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
