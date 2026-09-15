import 'dart:io';

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import 'work_steps_privacy.dart';

/// Native HealthKit / Health Connect — kun STEPS, kun etter frivillig samtykke.
///
/// APPLE/GOOGLE: See [work_steps_privacy.dart]. MAVI employees only. No tracking.
Future<bool> isSupported() async {
  return Platform.isIOS || Platform.isAndroid;
}

Future<bool> requestAuthorization() async {
  // Request OS permissions only after in-app consent (caller must ensure that).
  if (Platform.isAndroid) {
    await Permission.activityRecognition.request();
  }

  final health = Health();
  await health.configure();

  const types = [HealthDataType.STEPS];
  const permissions = [HealthDataAccess.READ];

  // Read-only: we never write health data.
  final ok = await health.requestAuthorization(types, permissions: permissions);
  return ok;
}

Future<int?> stepsToday() async {
  final health = Health();
  await health.configure();

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  try {
    final total = await health.getTotalStepsInInterval(start, now);
    return total;
  } catch (_) {
    // Fail closed — never invent data.
    return null;
  }
}

// Keep privacy constant referenced so reviewers find linkage from native code path.
// ignore: unused_element
String get _reviewPurpose => kWorkStepsShortPurpose;
