import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';

/// Forhåndsvis bilde/video + tekst før sending.
class ChatMediaSendSheet extends StatefulWidget {
  const ChatMediaSendSheet({
    super.key,
    required this.media,
  });

  final ChatPendingMedia media;

  static Future<({String caption, bool send})?> show(
    BuildContext context,
    ChatPendingMedia media,
  ) {
    return showModalBottomSheet<({String caption, bool send})?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ChatMediaSendSheet(media: media),
      ),
    );
  }

  @override
  State<ChatMediaSendSheet> createState() => _ChatMediaSendSheetState();
}

class _ChatMediaSendSheetState extends State<ChatMediaSendSheet> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              media.isVideo ? 'Forhåndsvis video' : 'Forhåndsvis bilde',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Kontroller innholdet før du sender — mottaker ser dette.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: media.isVideo
                  ? Container(
                      height: 180,
                      color: Colors.black87,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_circle_fill, size: 56, color: Colors.white),
                          const SizedBox(height: 8),
                          Text(
                            media.fileName,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : Image.memory(
                      Uint8List.fromList(media.bytes),
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caption,
              decoration: InputDecoration(
                labelText: 'Tekst (valgfritt)',
                hintText: 'Legg til kommentar…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, (caption: '', send: false)),
                    child: const Text('Avbryt'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      (caption: _caption.text.trim(), send: true),
                    ),
                    style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                    icon: const Icon(Icons.send),
                    label: const Text('Send nå'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
