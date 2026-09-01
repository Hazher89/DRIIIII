import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gjør URL-er i meldingstekst klikkbare.
class ChatLinkText extends StatelessWidget {
  const ChatLinkText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor,
  });

  final String text;
  final TextStyle style;
  final Color? linkColor;

  static final _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+|www\.[^\s]+)',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    final spans = <InlineSpan>[];
    var last = 0;
    final accent = linkColor ?? Theme.of(context).colorScheme.primary;

    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final raw = m.group(0)!;
      final url = raw.startsWith('http') ? raw : 'https://$raw';
      spans.add(
        TextSpan(
          text: raw,
          style: style.copyWith(color: accent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }

    return RichText(text: TextSpan(children: spans));
  }
}
