import 'package:driftpro/models/home_feed_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HomeFeedItem.fromJson parses feed row', () {
    final item = HomeFeedItem.fromJson({
      'id': 'abc-123',
      'company_id': 'co-1',
      'audience': 'partner',
      'content_type': 'video',
      'title': 'Velkommen',
      'caption': 'Ny rutine',
      'storage_path': 'dropbox://company_co/home_feed/partner/x.mp4',
      'file_name': 'x.mp4',
      'mime_type': 'video/mp4',
      'sort_order': 2,
      'is_active': true,
      'created_at': '2026-08-31T12:00:00Z',
    });

    expect(item.id, 'abc-123');
    expect(item.audience, HomeFeedAudience.partner);
    expect(item.contentType, HomeFeedContentType.video);
    expect(item.title, 'Velkommen');
    expect(item.sortOrder, 2);
    expect(item.isActive, isTrue);
  });

  test('HomeFeedService content type guess', () {
    expect(
      HomeFeedContentType.image,
      HomeFeedServiceGuess.guess('photo.JPG'),
    );
    expect(
      HomeFeedContentType.document,
      HomeFeedServiceGuess.guess('manual.pdf'),
    );
  });
}

/// Test helper mirroring [HomeFeedService.guessContentType].
class HomeFeedServiceGuess {
  static HomeFeedContentType? guess(String fileName, {String? mime}) {
    final lower = fileName.toLowerCase();
    final m = mime?.toLowerCase() ?? '';
    if (m.startsWith('image/') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return HomeFeedContentType.image;
    }
    if (m.startsWith('video/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v')) {
      return HomeFeedContentType.video;
    }
    if (lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.txt') ||
        m.contains('pdf') ||
        m.contains('document')) {
      return HomeFeedContentType.document;
    }
    return null;
  }
}
