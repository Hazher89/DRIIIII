import 'work_steps_health_auth_result.dart';

export 'work_steps_health_auth_result.dart';

Future<bool> isSupported() async => false;

Future<WorkStepsHealthAuthResult> requestAuthorization() async {
  return const WorkStepsHealthAuthResult(
    ok: false,
    message: 'Skritt synkes i DriftPro-appen på iPhone eller Android.',
  );
}

Future<void> installHealthConnect() async {}

Future<int?> stepsToday() async => null;
