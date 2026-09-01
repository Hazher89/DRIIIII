import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../models/chat/chat_models.dart';
import 'chat_media_viewer.dart';

/// Galleri over alle bilder/video i et rom.
class ChatMediaGallerySheet extends StatelessWidget {
  const ChatMediaGallerySheet({super.key, required this.messages});

  final List<ChatMessage> messages;

  static Future<void> show(BuildContext context, List<ChatMessage> messages) {
    final media = messages.where((m) {
      if (m.isDeleted || m.attachments.isEmpty) return false;
      final a = m.attachments.first;
      return PartnerChatService.attachmentIsImage(a, m.messageType) ||
          PartnerChatService.attachmentIsVideo(a, m.messageType);
    }).toList();
    if (media.isEmpty) {
      return showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Ingen media i denne samtalen ennå.', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChatMediaGallerySheet(messages: media),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('Media i samtalen', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            Text(
              '${messages.length} filer',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                controller: scroll,
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final m = messages[i];
                  final att = m.attachments.first;
                  final isVideo = PartnerChatService.attachmentIsVideo(att, m.messageType);
                  final url = att.signedUrl;
                  return GestureDetector(
                    onTap: url == null
                        ? null
                        : () {
                            if (isVideo) {
                              ChatMediaViewer.openVideo(context, url);
                            } else {
                              ChatMediaViewer.openImage(context, url);
                            }
                          },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url != null && !isVideo)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.videocam_rounded, color: Colors.white54),
                          ),
                        if (isVideo)
                          const Center(
                            child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 36),
                          ),
                        Positioned(
                          left: 4,
                          bottom: 4,
                          right: 4,
                          child: Text(
                            m.senderName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
