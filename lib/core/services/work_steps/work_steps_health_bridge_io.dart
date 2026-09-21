import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import 'work_steps_health_auth_result.dart';
import 'work_steps_privacy.dart';

Health _health() => Health();

const _stepTypes = [HealthDataType.STEPS];
const _stepAccess = [HealthDataAccess.READ];

Future<bool> isSupported() async {
  return Platform.isIOS || Platform.isAndroid;
}

Future<void> _configure() async {
  await _health().configure();
}

/// Android: Health Connect må være installert. iOS: alltid klar.
Future<WorkStepsHealthAuthResult?> ensurePlatformReady() async {
  if (Platform.isAndroid) {
    await _configure();
    final available = await _health().isHealthConnectAvailable();
    if (!available) {
      return const WorkStepsHealthAuthResult(
        ok: false,
        needsHealthConnectInstall: true,
        message:
            'Installér Google Health Connect for å lese skritt, '
            'og åpne DriftPro igjen.',
      );
    }
    final activity = await Permission.activityRecognition.request();
    if (!activity.isGranted) {
      return const WorkStepsHealthAuthResult(
        ok: false,
        message:
            'Tillat «Fysisk aktivitet» / Activity Recognition for DriftPro '
            'i systeminnstillingene.',
      );
    }
  } else {
    await _configure();
  }
  return null; // ready
}

/// Ber om lesetilgang til skritt. Verifiserer med faktisk lesing.
Future<WorkStepsHealthAuthResult> requestAuthorization() async {
  final blocked = await ensurePlatformReady();
  if (blocked != null) return blocked;

  try {
    final asked = await _health().requestAuthorization(
      _stepTypes,
      permissions: _stepAccess,
    );

    // iOS: true = dialog vist OK (Apple sier ikke om READ ble gitt).
    // Android: true = tillatelse gitt.
    if (Platform.isAndroid && !asked) {
      return const WorkStepsHealthAuthResult(
        ok: false,
        message:
            'Tillatelse til skritt ble ikke gitt i Health Connect. '
            'Åpne Health Connect → App-tillatelser → DriftPro.',
      );
    }

    // Verifiser at vi faktisk kan lese (iOS + Android).
    final probe = await stepsToday();
    if (probe == null && Platform.isAndroid) {
      final has = await _health().hasPermissions(
        _stepTypes,
        permissions: _stepAccess,
      );
      if (has == false) {
        return const WorkStepsHealthAuthResult(
          ok: false,
          message:
              'Health Connect har ikke gitt DriftPro tilgang til skritt. '
              'Slå på Skritt for DriftPro i Health Connect.',
        );
      }
    }

    // iOS: probe null kan bety nekting ELLER ingen data ennå — tillat aktivering;
    // synk vil feile tydelig hvis lesing fortsatt blokkeres.
    return WorkStepsHealthAuthResult(
      ok: true,
      stepsProbe: probe,
      message: probe == null
          ? 'Tillatelse er bedt om. Hvis skritt ikke synkes, sjekk Apple Helse → Deling → DriftPro.'
          : null,
    );
  } catch (e) {
    debugPrint('WorkStepsHealthBridge.requestAuthorization: $e');
    final msg = e.toString();
    if (msg.contains('Health Connect') || msg.contains('health connect')) {
      return const WorkStepsHealthAuthResult(
        ok: false,
        needsHealthConnectInstall: true,
        message: 'Health Connect mangler eller er utilgjengelig. Installér appen fra Play Store.',
      );
    }
    return WorkStepsHealthAuthResult(
      ok: false,
      message: 'Kunne ikke be om helsetilgang: $e',
    );
  }
}

Future<void> installHealthConnect() async {
  if (!Platform.isAndroid) return;
  await _configure();
  await _health().installHealthConnect();
}

/// Dagens skritt (lokal midnatt → nå). Null = lesing feilet.
Future<int?> stepsToday() async {
  try {
    await _configure();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    final total = await _health().getTotalStepsInInterval(start, now);
    if (total != null) return total.clamp(0, 200000);

    // Fallback: summer enkeltpunkter (noen enheter / HC-versjoner).
    final points = await _health().getHealthDataFromTypes(
      types: _stepTypes,
      startTime: start,
      endTime: now,
    );
    if (points.isEmpty) {
      // Tomt kan være «0 skritt» med tillatelse — returner 0 heller enn null
      // når hasPermissions ikke er false.
      if (Platform.isAndroid) {
        final has = await _health().hasPermissions(
          _stepTypes,
          permissions: _stepAccess,
        );
        if (has == false) return null;
      }
      return 0;
    }

    var sum = 0.0;
    for (final p in points) {
      final v = p.value;
      if (v is NumericHealthValue) {
        sum += v.numericValue;
      }
    }
    return sum.round().clamp(0, 200000);
  } catch (e) {
    debugPrint('WorkStepsHealthBridge.stepsToday: $e');
    return null;
  }
}

// Keep privacy constant referenced for Apple/Google review linkage.
// ignore: unused_element
String get _reviewPurpose => kWorkStepsShortPurpose;
