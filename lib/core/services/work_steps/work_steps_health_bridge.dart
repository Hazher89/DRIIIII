import 'work_steps_health_auth_result.dart';
import 'work_steps_health_bridge_stub.dart'
    if (dart.library.io) 'work_steps_health_bridge_io.dart' as impl;

export 'work_steps_health_auth_result.dart';

/// Plattformbro for skritt (HealthKit / Health Connect). Web = stub.
abstract final class WorkStepsHealthBridge {
  static Future<bool> isSupported() => impl.isSupported();

  static Future<WorkStepsHealthAuthResult> requestAuthorization() =>
      impl.requestAuthorization();

  static Future<void> installHealthConnect() => impl.installHealthConnect();

  static Future<int?> stepsToday() => impl.stepsToday();
}
