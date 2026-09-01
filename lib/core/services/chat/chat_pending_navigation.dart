/// Holder rom-ID fra push/deep link til hub har åpnet.
abstract final class ChatPendingNavigation {
  static String? _roomId;

  static void setRoom(String roomId) {
    final trimmed = roomId.trim();
    if (trimmed.isEmpty) return;
    _roomId = trimmed;
  }

  static String? takeRoomId() {
    final id = _roomId;
    _roomId = null;
    return id;
  }
}
