// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openExternalUrl(String url) async {
  final opened = html.window.open(url, '_blank');
  return opened != null;
}
