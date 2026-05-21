import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../constants/wallboard_location.dart';

class TransitDeparture {
  final String line;
  final String transportMode;
  final String destination;
  final DateTime departure;
  final String stopName;

  const TransitDeparture({
    required this.line,
    required this.transportMode,
    required this.destination,
    required this.departure,
    required this.stopName,
  });

  int minutesUntil(DateTime now) => departure.difference(now).inMinutes.clamp(0, 999);
}

/// Avganger gruppert per holdeplass/stasjon.
class StopDepartures {
  final String stopId;
  final String stopName;
  final double distanceM;
  final List<TransitDeparture> departures;

  const StopDepartures({
    required this.stopId,
    required this.stopName,
    required this.distanceM,
    required this.departures,
  });

  bool get hasRail => departures.any((d) => d.transportMode == 'rail');
  bool get hasMetro => departures.any((d) => d.transportMode == 'metro');
}

class EnturDeparturesService {
  static const _graphqlUrl = 'https://api.entur.io/journey-planner/v3/graphql';
  static const _clientName = 'mavi-logistikk-driftpro-infoskjerm';

  static Future<List<StopDepartures>> fetchNearby({
    double lat = WallboardLocation.latitude,
    double lon = WallboardLocation.longitude,
    int maxStops = 5,
    int departuresPerStop = 3,
  }) async {
    const query = r'''
query($lat: Float!, $lon: Float!) {
  nearest(
    latitude: $lat
    longitude: $lon
    filterByPlaceTypes: [stopPlace]
    maximumDistance: 1300
  ) {
    edges {
      node {
        distance
        place {
          ... on StopPlace {
            id
            name
            estimatedCalls(timeRange: 5400, numberOfDepartures: 6) {
              expectedDepartureTime
              destinationDisplay { frontText }
              serviceJourney {
                journeyPattern {
                  line { publicCode transportMode }
                }
              }
            }
          }
        }
      }
    }
  }
}
''';

    final res = await http
        .post(
          Uri.parse(_graphqlUrl),
          headers: {
            'Content-Type': 'application/json',
            'ET-Client-Name': _clientName,
          },
          body: jsonEncode({
            'query': query,
            'variables': {'lat': lat, 'lon': lon},
          }),
        )
        .timeout(const Duration(seconds: 16));

    if (res.statusCode != 200) return [];

    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['errors'] != null) return [];

    final edges =
        (json['data'] as Map?)?['nearest']?['edges'] as List<dynamic>? ?? [];

    final now = DateTime.now();
    final stops = <StopDepartures>[];
    final seenIds = <String>{};

    for (final edge in edges) {
      if (stops.length >= maxStops + 4) break;

      final node = (edge as Map)['node'] as Map<String, dynamic>?;
      final place = node?['place'] as Map<String, dynamic>?;
      if (place == null || place['name'] == null) continue;

      final stopId = place['id'] as String? ?? '';
      if (stopId.isEmpty || seenIds.contains(stopId)) continue;

      final stopName = place['name'] as String;
      final distance = (node?['distance'] as num?)?.toDouble() ?? 9999;
      final calls = place['estimatedCalls'] as List<dynamic>? ?? [];
      final departures = <TransitDeparture>[];

      for (final call in calls) {
        final c = call as Map<String, dynamic>;
        final timeStr = c['expectedDepartureTime'] as String?;
        if (timeStr == null) continue;
        final departure = DateTime.tryParse(timeStr);
        if (departure == null ||
            departure.isBefore(now.subtract(const Duration(minutes: 2)))) {
          continue;
        }

        final dest =
            (c['destinationDisplay'] as Map?)?['frontText'] as String? ?? '';
        final lineMap = ((c['serviceJourney'] as Map?)?['journeyPattern']
            as Map?)?['line'] as Map<String, dynamic>?;
        final line = lineMap?['publicCode'] as String? ?? '?';
        final mode = lineMap?['transportMode'] as String? ?? 'bus';

        departures.add(TransitDeparture(
          line: line,
          transportMode: mode,
          destination: dest,
          departure: departure.toLocal(),
          stopName: stopName,
        ));
      }

      if (departures.isEmpty) continue;
      seenIds.add(stopId);
      departures.sort((a, b) => a.departure.compareTo(b.departure));

      stops.add(StopDepartures(
        stopId: stopId,
        stopName: stopName,
        distanceM: distance,
        departures: departures.take(departuresPerStop).toList(),
      ));
    }

    stops.sort((a, b) {
      int rank(StopDepartures s) {
        if (s.hasRail) return 0;
        if (s.hasMetro) return 1;
        if (s.stopName.toLowerCase().contains('stasjon')) return 2;
        return 3;
      }

      final ra = rank(a);
      final rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return a.distanceM.compareTo(b.distanceM);
    });

    return stops.take(maxStops).toList();
  }
}
