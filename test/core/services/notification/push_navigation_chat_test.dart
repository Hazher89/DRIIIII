import 'package:driftpro/core/services/notification/push_navigation_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat_message push parses room_id', () {
    final target = PushNavigationTarget.fromMap({
      'type': 'chat_message',
      'room_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    });

    expect(target, isNotNull);
    expect(target!.kind, PushNavKind.chatMessage);
    expect(target.id, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    expect(target.maviPath, contains('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'));
  });

  test('chat_message push falls back to reference_id', () {
    final target = PushNavigationTarget.fromMap({
      'type': 'chat_message',
      'reference_type': 'chat_messages',
      'reference_id': '11111111-2222-3333-4444-555555555555',
    });

    expect(target?.kind, PushNavKind.chatMessage);
    expect(target?.id, '11111111-2222-3333-4444-555555555555');
  });
}
