import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildPlatformMediaView(String url, {bool isAudio = false}) {
  return Center(
    child: ElevatedButton.icon(
      onPressed: () => launchUrl(Uri.parse(url)),
      icon: Icon(isAudio ? Icons.audiotrack : Icons.play_circle),
      label: Text(isAudio ? 'Spill av lyd' : 'Spill av video'),
    ),
  );
}
