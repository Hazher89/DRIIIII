// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<bool> chatWebNotificationsSupported() async => html.Notification.supported == true;

Future<bool> chatWebNotificationsGranted() async =>
    html.Notification.permission == 'granted';

Future<bool> requestChatWebNotificationPermission() async {
  if (html.Notification.supported != true) return false;
  if (html.Notification.permission == 'granted') return true;
  final result = await html.Notification.requestPermission();
  return result == 'granted';
}

void showChatWebNotification({
  required String title,
  required String body,
  String? roomId,
  void Function(String roomId)? onTap,
}) {
  if (html.Notification.permission != 'granted') return;
  final n = html.Notification(
    title,
    body: body,
    tag: roomId,
    icon: '/icons/Icon-192.png',
  );
  if (roomId != null && onTap != null) {
    n.onClick.listen((_) {
      onTap(roomId);
      n.close();
    });
  }
}

bool chatWebPageIsHidden() => html.document.hidden == true;
