/// Ingen nettleservarsler utenfor web.
Future<bool> chatWebNotificationsSupported() async => false;

Future<bool> chatWebNotificationsGranted() async => false;

Future<bool> requestChatWebNotificationPermission() async => false;

void showChatWebNotification({
  required String title,
  required String body,
  String? roomId,
  void Function(String roomId)? onTap,
}) {}

bool chatWebPageIsHidden() => false;
