/// Hvilket rom brukeren ser nå — for å unngå unødvige varsler.
abstract final class ChatPresenceService {
  static String? _openRoomId;

  static String? get openRoomId => _openRoomId;

  static void setOpenRoom(String? roomId) {
    _openRoomId = roomId;
  }
}
