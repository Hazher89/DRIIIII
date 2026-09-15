import 'work_steps_health_bridge_stub.dart'
    if (dart.library.io) 'work_steps_health_bridge_io.dart' as impl;

/// Plattformbro for skritt (HealthKit / Health Connect). Web = stub.
abstract final class WorkStepsHealthBridge {
  static Future<bool> isSupported() => impl.isSupported();

  static Future<bool> requestAuthorization() => impl.requestAuthorization();

  static Future<int?> stepsToday() => impl.stepsToday();
}
