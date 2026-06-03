import 'package:url_launcher/url_launcher.dart';

/// MAVI kjørekontor — brukes i partner- og sjåførportaler.
const String kKjorekontorPhoneE164 = '+4740175012';

const String kKjorekontorPhoneDisplay = '40 17 50 12';

const String kKjorekontorPhoneDial = '004740175012';

Future<bool> launchKjorekontorPhone() async {
  final uri = Uri(scheme: 'tel', path: kKjorekontorPhoneE164);
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri);
  }
  return launchUrl(Uri.parse('tel:$kKjorekontorPhoneDial'));
}
