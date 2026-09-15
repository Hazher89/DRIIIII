/// Web stub — leiebil-kiosk kjører ikke i nettleser.
class DriveMonitorOfflineQueue {
  DriveMonitorOfflineQueue(this.sessionId);
  final String sessionId;

  Future<void> enqueueSamples(List<Map<String, dynamic>> rows) async {}
  Future<void> enqueueEvents(List<Map<String, dynamic>> rows) async {}

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> peek() async =>
      (<Map<String, dynamic>>[], <Map<String, dynamic>>[]);

  Future<void> replace({
    required List<Map<String, dynamic>> samples,
    required List<Map<String, dynamic>> events,
  }) async {}

  Future<void> clear() async {}
}
