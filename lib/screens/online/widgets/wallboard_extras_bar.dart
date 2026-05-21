import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/wallboard_location.dart';
import '../../../core/theme/wallboard_palette.dart';
import '../../../core/services/wallboard/entur_departures_service.dart';
import '../../../core/services/wallboard/open_meteo_weather_service.dart';

class WallboardExtrasBar extends StatelessWidget {
  final WallboardWeather? weather;
  final List<StopDepartures> stops;

  const WallboardExtrasBar({
    super.key,
    required this.weather,
    required this.stops,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WallboardPalette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WallboardPalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeatherChip(weather: weather),
          Container(
            width: 1,
            height: 72,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: WallboardPalette.divider,
          ),
          Expanded(child: _TransitBoard(stops: stops)),
        ],
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  final WallboardWeather? weather;

  const _WeatherChip({required this.weather});

  IconData _icon(String key) {
    switch (key) {
      case 'clear':
        return Icons.wb_sunny_rounded;
      case 'partly':
        return Icons.wb_cloudy_rounded;
      case 'rain':
      case 'drizzle':
      case 'showers':
        return Icons.water_drop_rounded;
      case 'snow':
        return Icons.ac_unit_rounded;
      case 'thunder':
        return Icons.thunderstorm_rounded;
      case 'fog':
        return Icons.foggy;
      default:
        return Icons.cloud_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = weather;
    if (w == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_queue, color: WallboardPalette.textMuted, size: 28),
          SizedBox(width: 10),
          Text('Henter vær …', style: TextStyle(color: WallboardPalette.textSecondary, fontSize: 12)),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon(w.iconKey), color: WallboardPalette.weatherIcon, size: 32),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${w.temperatureC.round()}°',
              style: const TextStyle(
                color: WallboardPalette.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${w.description} · vind ${w.windKmh.round()} km/t',
              style: const TextStyle(color: WallboardPalette.textSecondary, fontSize: 10),
            ),
            Text(
              WallboardLocation.addressLabel,
              style: const TextStyle(color: WallboardPalette.textMuted, fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransitBoard extends StatelessWidget {
  final List<StopDepartures> stops;

  const _TransitBoard({required this.stops});

  Color _modeColor(String mode) {
    switch (mode) {
      case 'metro':
        return const Color(0xFFE53935);
      case 'tram':
        return const Color(0xFF00897B);
      case 'rail':
        return const Color(0xFF5E35B1);
      default:
        return const Color(0xFF1565C0);
    }
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'metro':
        return 'T-bane';
      case 'tram':
        return 'Trikk';
      case 'rail':
        return 'Tog';
      default:
        return 'Buss';
    }
  }

  String _stopBadge(StopDepartures stop) {
    if (stop.hasRail) return 'Tog';
    if (stop.hasMetro) return 'T-bane';
    return 'Buss';
  }

  Color _stopBadgeColor(StopDepartures stop) {
    if (stop.hasRail) return WallboardPalette.transitRail;
    if (stop.hasMetro) return WallboardPalette.transitMetro;
    return WallboardPalette.transitBus;
  }

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kollektiv nær ${WallboardLocation.addressLabel}',
            style: const TextStyle(
              color: WallboardPalette.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Henter avganger …',
            style: TextStyle(color: WallboardPalette.textMuted, fontSize: 11),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final timeFmt = DateFormat('HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kollektiv nær ${WallboardLocation.addressLabel}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: stops.map((stop) {
              final badgeColor = _stopBadgeColor(stop);
              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: WallboardPalette.cardInset,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _stopBadge(stop),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            stop.stopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: WallboardPalette.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${stop.distanceM.round()} m',
                          style: const TextStyle(color: WallboardPalette.textMuted, fontSize: 8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...stop.departures.map((d) {
                      final min = d.minutesUntil(now);
                      final minsLabel = min <= 0 ? 'nå' : '$min min';
                      final accent = _modeColor(d.transportMode);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                d.line,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.destination,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: WallboardPalette.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_modeLabel(d.transportMode)} ${timeFmt.format(d.departure)} · $minsLabel',
                                    style: const TextStyle(
                                      color: WallboardPalette.textSecondary,
                                      fontSize: 8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
