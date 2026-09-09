/// Stub — brukes bare hvis verken web eller IO er tilgjengelig.
class AssistantFabPositionStore {
  AssistantFabPositionStore._();

  static ({double left, double top})? load(String userId) => null;

  static Future<({double left, double top})?> loadAsync(String userId) async =>
      null;

  static void save(String userId, {required double left, required double top}) {}
}
