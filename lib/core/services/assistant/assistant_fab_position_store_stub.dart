/// Stub — FAB-posisjon brukes kun på web.
class AssistantFabPositionStore {
  AssistantFabPositionStore._();

  static ({double left, double top})? load(String userId) => null;

  static void save(String userId, {required double left, required double top}) {}
}
