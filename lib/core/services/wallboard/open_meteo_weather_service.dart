import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../constants/wallboard_location.dart';

class WallboardWeather {
  final double temperatureC;
  final double windKmh;
  final int weatherCode;
  final String description;
  final String iconKey;

  const WallboardWeather({
    required this.temperatureC,
    required this.windKmh,
    required this.weatherCode,
    required this.description,
    required this.iconKey,
  });
}

class OpenMeteoWeatherService {
  static const _base = 'https://api.open-meteo.com/v1/forecast';

  static Future<WallboardWeather?> fetch({
    double lat = WallboardLocation.latitude,
    double lon = WallboardLocation.longitude,
  }) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: {
        'latitude': '$lat',
        'longitude': '$lon',
        'current': 'temperature_2m,weather_code,wind_speed_10m',
        'timezone': 'Europe/Oslo',
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>?;
    if (current == null) return null;

    final code = (current['weather_code'] as num?)?.toInt() ?? 0;
    final meta = _wmoMeta(code);
    return WallboardWeather(
      temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      windKmh: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      weatherCode: code,
      description: meta.$1,
      iconKey: meta.$2,
    );
  }

  static (String, String) _wmoMeta(int code) {
    if (code == 0) return ('Klart', 'clear');
    if (code <= 3) return ('Delvis skyet', 'partly');
    if (code == 45 || code == 48) return ('Tåke', 'fog');
    if (code >= 51 && code <= 57) return ('Yr', 'drizzle');
    if (code >= 61 && code <= 67) return ('Regn', 'rain');
    if (code >= 71 && code <= 77) return ('Snø', 'snow');
    if (code >= 80 && code <= 82) return ('Byger', 'showers');
    if (code >= 95) return ('Torden', 'thunder');
    return ('Skyet', 'cloud');
  }
}
