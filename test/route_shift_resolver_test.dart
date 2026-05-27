import 'package:driftpro/core/services/partner/postal_code_registry.dart';
import 'package:driftpro/core/services/partner/postal_region_mapper.dart';
import 'package:driftpro/core/services/partner/route_pdf_text_service.dart';
import 'package:driftpro/core/services/partner/route_shift_resolver.dart';
import 'package:driftpro/core/services/partner/route_time_band.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => null,
    );
    await PostalCodeRegistry.ensureLoaded();
  });

  test('Trip Overview uten komma før +47 — Romerike, ikke Geilo', () async {
    const text = '''
6102686487 Mavi Logistikk 0484 Oslo HUB Oslo
1 4106102309 Nes Kommune Neskollen skole Melkevegen 19 2165 HVAM +4741234567 08:00 17:00
2 4106106686 Nes Kommune Boligavdelingen Nedre Hagaveg 63 2150 Aarnes +4798765432 08:00 17:00
4 4106108680 Ciupitu Flaggspettvegen 26B 2032 MAURA +4741111111 08:00 13:00
5 4106112176 Per Rune Aamodtalleen 4 2008 Fjerdingby +4742222222 08:00 17:00
6 4106087577 Piotr Skustadgata 47 1395 Hvalstad +4743333333 12:00 17:00
''';

    final stops = RoutePdfTextService.parseCustomers(text);
    expect(stops.length, 5);

    final analysis = await RouteShiftResolver.analyzePdfText(text);
    expect(analysis.dominantRegion, 'Indre');
    expect(analysis.hasConfidentRegion, isTrue);
    expect(analysis.dominantRegion, isNot('Geilo'));
  });

  test('Hvam og Årnes mapper til Indre', () {
    expect(PostalRegionMapper.stedToRegion('Hvam'), 'Indre');
    expect(PostalRegionMapper.stedToRegion('Årnes'), 'Indre');
    expect(PostalRegionMapper.stedToRegion('Jaren'), 'Hadeland');
  });

  test('SAP Bilal M0125 — alle 4 stopp + flertall Indre', () async {
    const text = '''
1 4106078451 thuc van nguyen , Munkevegen 180, 1061 Oslo , +47 (94728973) 07:00 09:00
2 4106079600 Anders Grotterød , Rastastien 58a, 1476 Rasta , +47 (95041345) 07:00 09:00
3 4106096701, 4106078107, 4106078108 Unify Sti , Bibliotekgata 30, 1473 LØRENSKOG , +47 (41348436) 08:00 09:00
4 4106077220 Johnny Brevik , Torvgata 15D, 2000 Lillestrøm , +47 (95988888) 07:00 09:00
''';
    final stops = RoutePdfTextService.parseCustomers(text);
    expect(stops.length, 4);
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.hasConfidentRegion, isTrue);
    expect(a.dominantRegion, 'Indre');
  });

  test('SAP Abed M0023 — 3 stopp Indre', () async {
    const text = '''
1 4106072720 Ærling Sæther, Lønneveien 6A 2020 Skedsmokorset, +47 (90108444) 07:00 09:00
2 4106070359 Tove-Lill Duran, Kanalen 3 1900 Fetsund, +47 (95460459) 08:00 17:00
3 4106070357 Anders Hjelle, Leikvangveien 6 1488 Hakadal, +47 (92832705) 08:00 17:00
''';
    expect(RoutePdfTextService.parseCustomers(text).length, 3);
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.hasConfidentRegion, isTrue);
    expect(a.dominantRegion, 'Indre');
  });

  test('1 stopp — får område og best-effort', () async {
    const text = '''
1 4106077220 Johnny Brevik , Torvgata 15D, 2000 Lillestrøm , +47 (95988888) 07:00 09:00
''';
    expect(RoutePdfTextService.parseCustomers(text).length, 1);
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.dominantRegion, 'Indre');
    expect(a.bestEffortRegion, 'Indre');
    expect(a.hasConfidentRegion, isTrue);
  });

  test('2 stopp ulike områder — første stopp avgjør', () async {
    const text = '''
1 4106071840 Gro Iversen Herfordts Gate 9 1532 Moss +47 (92061347) 15:00 22:00
2 4106077220 Johnny Brevik Torvgata 15D 2000 Lillestrøm +47 (95988888) 07:00 09:00
''';
    expect(RoutePdfTextService.parseCustomers(text).length, 2);
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.firstStopRegion, 'Østfold');
    expect(a.dominantRegion, 'Østfold');
    expect(a.bestEffortRegion, 'Østfold');
  });

  test('Romerike i fritekst → Indre', () {
    expect(PostalRegionMapper.regionFromFreeText('Geilo kveldsrute med stopp i Romerike'), 'Indre');
  });

  test('Telefon med mellomrom i Trip Overview', () {
    const text = '''
1 4106056634 Grethe Aastveit Kongsvingergata 9g 0464 Oslo +47 918 35 421 08:00 13:00
''';
    expect(RoutePdfTextService.parseCustomers(text).length, 1);
  });

  test('Oslo postnr og Kongsvingergata — ikke Kongsvinger-område', () async {
    expect(PostalRegionMapper.stedToRegion('Oslo'), 'Oslo');
    expect(PostalRegionMapper.stedToRegion('Kongsvingergata'), isNull);
    expect(PostalCodeRegistry.lookupSted('0464'), 'Oslo');

    const text = '''
Start date 27.05.26
0484 Oslo HUB
1 4106056634 Grethe Aastveit Kongsvingergata 9g 0464 Oslo +47 91835421 08:00 13:00
2 4106077220 Johnny Brevik Torvgata 15D 2000 Lillestrøm +47 95988888 07:00 09:00
''';
    expect(RoutePdfTextService.parseRouteDate(text), DateTime(2026, 5, 27));
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.dominantRegion, isNot('Kongsvinger'));
    expect(a.regionCounts['Kongsvinger'], anyOf(isNull, 0));
  });

  test('SAP M0124 — kunde (Rolvsøy) uten +47, 08–16 → Østfold dag', () async {
    const text = '''
Start date 26.05.26
Resource ID NO_O_M0124
1 4106081371 Ronny Helstad (Rolvsøy) CURB 08:00 16:00
2 4106094489 Anita Kristiansen (Borgenhaugen) CURB 08:00 16:00
3 4106087267 Tor Odd Warth (Borgenhaugen) CURB 08:00 16:00
4 4106086564 Tdm AS (Tistedal) CURB 08:00 16:00
5 4106094484 Therese Gjessing (Tistedal) CURB 08:00 16:00
''';
    final stops = RoutePdfTextService.parseCustomers(text);
    expect(stops.length, 5);
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.bestEffortRegion, 'Østfold');
    expect(RouteTimeBand.inferFromStops(stops), 'dag');
  });

  test('SAP M0023 — blandet 08–16 og 16–22 → dag (tidligste start 08:00)', () async {
    const text = '''
1 4106116768 Erik Pettersen, Villavegen 4, 2240 Magnor, +47 (95416636) CURB RETG 08:00 16:00
2 4106102670 Ellen Brandt, Svensrudvegen 19, 2240 Magnor, +47 (97000550) SITES 08:00 16:00
3 4106089057 Rønnaug Eike, Vålvassvegen 329, 2230 Skotterud, +47 (48168777) SITE RETG 08:00 16:00
4 4106112745 Asgeir Velten, Kastellvegen 11, 2080 Eidsvoll, +47 (95912451) SITES RETGS DEVUN 16:00 22:00
''';
    final stops = RoutePdfTextService.parseCustomers(text);
    expect(stops.length, 4);
    expect(RouteTimeBand.inferFromStops(stops), 'dag');
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.bestEffortRegion, isNotNull);
  });

  test('RouteTimeBand — start 16:00 er kveld', () {
    expect(RouteTimeBand.fromMinutes(16 * 60), 'kveld');
    expect(RouteTimeBand.fromMinutes(11 * 60 + 30), 'dag');
    expect(RouteTimeBand.fromMinutes(11 * 60 + 31), 'kveld');
  });

  test('SAP M0086 — Kolsås 08–13 dag', () async {
    const text = '''
Start date 15.04.26
1 4106137729 Astrid Sævig, Riskegrenna 31, 1352 Kolsås, +47 (99621787) RETG 08:00 13:00
''';
    final stops = RoutePdfTextService.parseCustomers(text);
    expect(stops.length, 1);
    expect(RouteTimeBand.inferFromStops(stops), 'dag');
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.bestEffortRegion, 'Bærum');
  });

  test('SAP Abdallah M0060 — 3 stopp Østfold kveld', () async {
    const text = '''
1 4106071840 Gro Iversen Herfordts Gate 9 1532 Moss +47 (92061347) 15:00 22:00
2 4106070449,4106070448 Stine Jakobsen Fjordstien 18 1765 Halden +47 (41211678) 15:00 22:00
3 4106071981,4106071982 Merete Nilsen Blokkveien 4 1785 Halden +47 (92616224) 15:00 22:00
''';
    expect(RoutePdfTextService.parseCustomers(text).length, 3);
    final a = await RouteShiftResolver.analyzePdfText(text);
    expect(a.hasConfidentRegion, isTrue);
    expect(a.dominantRegion, 'Østfold');
    final start = RoutePdfTextService.parseEarliestStopStartTime(text, routeDate: DateTime(2026, 4, 8));
    expect(RouteTimeBand.fromDateTime(start), 'kveld');
  });
}
