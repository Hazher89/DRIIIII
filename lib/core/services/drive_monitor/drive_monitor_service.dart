import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../native_permissions_service.dart';
import '../supabase_service.dart';
import '../../../models/user_profile.dart';
import 'drive_monitor_offline_queue.dart';

/// Leiebil-sporing: GPS + sensorer → sessions/events i Supabase (+ offline-kø).
class DriveMonitorService {
  DriveMonitorService._();

  static SupabaseClient get _db => SupabaseService.client;

  static String hashPin(String pin) {
    final bytes = utf8.encode(pin.trim());
    return sha256.convert(bytes).toString();
  }

  static Future<List<Map<String, dynamic>>> listDeviceUsers(String companyId) async {
    final rows = await _db
        .from('profiles')
        .select(
          'id, full_name, employee_number, email, drive_monitor_device, drive_monitor_unit_name',
        )
        .eq('company_id', companyId)
        .eq('drive_monitor_device', true)
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> searchEmployees(
    String companyId,
    String query,
  ) async {
    final q = query.trim();
    final filter = _db
        .from('profiles')
        .select(
          'id, full_name, employee_number, email, drive_monitor_device, drive_monitor_unit_name',
        )
        .eq('company_id', companyId)
        .eq('is_active', true)
        .isFilter('partner_id', null);
    final rows = q.isEmpty
        ? await filter.order('full_name').limit(30)
        : await filter
            .or('full_name.ilike.%$q%,employee_number.ilike.%$q%,email.ilike.%$q%')
            .order('full_name')
            .limit(30);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> setDeviceUser(
    String profileId,
    bool enabled, {
    String? unitName,
  }) async {
    final patch = <String, dynamic>{
      'drive_monitor_device': enabled,
    };
    if (unitName != null) {
      patch['drive_monitor_unit_name'] =
          unitName.trim().isEmpty ? null : unitName.trim();
    }
    if (!enabled) {
      patch['drive_monitor_unit_name'] = null;
    }
    await _db.from('profiles').update(patch).eq('id', profileId);
  }

  static Future<void> renameDeviceUnit(String profileId, String unitName) async {
    final name = unitName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Enhetsnavn er påkrevd');
    }
    await _db.from('profiles').update({
      'drive_monitor_unit_name': name,
      'drive_monitor_device': true,
    }).eq('id', profileId);
  }

  /// Opprett ny innloggingsbruker kun for sporing + sett enhetsnavn.
  static Future<UserProfile> createTrackingUnit({
    required String companyId,
    required String unitName,
    required String employeeNumber,
    String? loginDisplayName,
  }) async {
    final name = unitName.trim();
    if (name.isEmpty) throw ArgumentError('Enhetsnavn er påkrevd');
    final profile = await SupabaseService.createEmployeeProfile(
      companyId: companyId,
      fullName: (loginDisplayName ?? name).trim(),
      employeeNumber: employeeNumber.trim(),
      jobTitle: 'Sporingsenhet',
      role: UserRole.ansatt,
    );
    await setDeviceUser(profile.id, true, unitName: name);
    return profile.copyWith(
      driveMonitorDevice: true,
      driveMonitorUnitName: name,
    );
  }

  static Future<Map<String, dynamic>?> fetchSettings(String companyId) async {
    final rows = await _db
        .from('drive_monitor_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    return rows;
  }

  static Future<void> saveExitPin(String companyId, String pin) async {
    await _db.from('drive_monitor_settings').upsert({
      'company_id': companyId,
      'exit_pin_hash': hashPin(pin),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<bool> verifyExitPin(String companyId, String pin) async {
    final settings = await fetchSettings(companyId);
    final hash = settings?['exit_pin_hash'] as String?;
    if (hash == null || hash.isEmpty) {
      return pin.trim() == '0000';
    }
    return hash == hashPin(pin);
  }

  static Future<List<Map<String, dynamic>>> listSessions({
    required String companyId,
    int limit = 120,
    bool? archived,
    DateTime? archiveDate,
  }) async {
    var q = _db
        .from('drive_monitor_sessions')
        .select()
        .eq('company_id', companyId);
    if (archived != null) {
      q = q.eq('is_archived', archived);
    }
    if (archiveDate != null) {
      final d =
          '${archiveDate.year.toString().padLeft(4, '0')}-${archiveDate.month.toString().padLeft(2, '0')}-${archiveDate.day.toString().padLeft(2, '0')}';
      q = q.eq('archive_date', d);
    }
    final rows = await q.order('started_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> listEvents({
    required String companyId,
    String? sessionId,
    int limit = 200,
  }) async {
    final base = _db
        .from('drive_monitor_events')
        .select()
        .eq('company_id', companyId);
    final rows = sessionId == null
        ? await base.order('recorded_at', ascending: false).limit(limit)
        : await base
            .eq('session_id', sessionId)
            .order('recorded_at', ascending: false)
            .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> listSamples({
    required String sessionId,
    int limit = 5000,
  }) async {
    final rows = await _db
        .from('drive_monitor_samples')
        .select()
        .eq('session_id', sessionId)
        .order('recorded_at')
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<Map<String, dynamic>> fetchMapPayload({
    required String companyId,
    String? sessionId,
    DateTime? archiveDate,
  }) async {
    final params = <String, dynamic>{
      'p_company_id': companyId,
      if (sessionId != null) 'p_session_id': sessionId,
      if (archiveDate != null)
        'p_archive_date':
            '${archiveDate.year.toString().padLeft(4, '0')}-${archiveDate.month.toString().padLeft(2, '0')}-${archiveDate.day.toString().padLeft(2, '0')}',
    };
    final res = await _db.rpc('get_drive_monitor_map_payload', params: params);
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'sessions': [], 'samples': [], 'events': []};
  }

  static Future<int> archivePreviousDays(String companyId) async {
    try {
      final res = await _db.rpc(
        'archive_drive_monitor_previous_days',
        params: {'p_company_id': companyId},
      );
      if (res is int) return res;
      if (res is num) return res.toInt();
      return int.tryParse('$res') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> listVehicles(String companyId) async {
    final rows = await _db
        .from('partner_vehicles')
        .select('id, unit_code, registration_number, partner_id, is_active')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('unit_code')
        .limit(200);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<String> startSession({
    required String companyId,
    required String deviceProfileId,
    String? partnerVehicleId,
    String? vehicleLabel,
  }) async {
    final row = await _db.from('drive_monitor_sessions').insert({
      'company_id': companyId,
      'device_profile_id': deviceProfileId,
      if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
      if (vehicleLabel != null) 'vehicle_label': vehicleLabel,
      'status': 'active',
      'is_archived': false,
    }).select('id').single();
    return row['id'] as String;
  }

  static Future<void> endSession(
    String sessionId, {
    required double score,
    required double km,
    required int eventCount,
    required int roughEventCount,
    double? maxSpeedKmh,
    double? avgSpeedKmh,
  }) async {
    final started = await _db
        .from('drive_monitor_sessions')
        .select('started_at')
        .eq('id', sessionId)
        .maybeSingle();
    final startedAt = DateTime.tryParse('${started?['started_at']}');
    final archiveDate = startedAt?.toLocal();
    final d = archiveDate ?? DateTime.now();
    final dateStr =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    await _db.from('drive_monitor_sessions').update({
      'status': 'ended',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'score': score,
      'km': km,
      'event_count': eventCount,
      'rough_event_count': roughEventCount,
      if (maxSpeedKmh != null) 'max_speed_kmh': maxSpeedKmh,
      if (avgSpeedKmh != null) 'avg_speed_kmh': avgSpeedKmh,
      'archive_date': dateStr,
      'is_archived': DateTime.now().toLocal().day != d.day ||
          DateTime.now().toLocal().difference(d).inHours >= 12,
    }).eq('id', sessionId);
  }
}

/// Live tracking-motor for én leiebil (kiosk) — kontinuerlig, offline-robust, Android FG.
class DriveMonitorTracker {
  DriveMonitorTracker({
    required this.companyId,
    required this.sessionId,
    this.hardBrakeMs2 = 3.5,
    this.hardAccelMs2 = 3.0,
    this.speedingKmh = 90,
    this.sharpTurnDeg = 42,
  });

  final String companyId;
  final String sessionId;
  final double hardBrakeMs2;
  final double hardAccelMs2;
  final double speedingKmh;
  final double sharpTurnDeg;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _flushTimer;
  Timer? _dayTimer;
  Timer? _pollTimer;

  late final DriveMonitorOfflineQueue _queue =
      DriveMonitorOfflineQueue(sessionId);

  double? _lastSpeed;
  DateTime? _lastPosAt;
  DateTime? _lastSampleAt;
  Position? _lastPos;
  Position? _lastSamplePos;
  double? _lastHeading;
  double _km = 0;
  int _eventCount = 0;
  int _roughCount = 0;
  double _liveSpeed = 0;
  double _maxSpeed = 0;
  double _speedSum = 0;
  int _speedN = 0;
  String _liveStatus = 'ok';
  DateTime? _lastEventAt;
  DateTime? _idleSince;
  bool _flushing = false;
  bool _online = true;

  final _sampleBuf = <Map<String, dynamic>>[];
  final _eventBuf = <Map<String, dynamic>>[];
  final _statusCtrl = StreamController<DriveMonitorLiveStatus>.broadcast();

  Stream<DriveMonitorLiveStatus> get statusStream => _statusCtrl.stream;
  double get km => _km;
  int get eventCount => _eventCount;
  int get roughCount => _roughCount;
  double get score {
    final penalty = (_roughCount * 12) + ((_eventCount - _roughCount) * 4);
    return (100 - penalty).clamp(0, 100).toDouble();
  }

  Future<void> start() async {
    // Always/background required for rental-vehicle kiosk tracking (not for staff).
    await NativePermissionsService.ensureBackgroundLocation();
    await WakelockPlus.enable();

    // Reload any pending offline data from previous crash/kill.
    final pending = await _queue.peek();
    _sampleBuf.addAll(pending.$1);
    _eventBuf.addAll(pending.$2);

    final settings = _androidLocationSettings();
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (_) {});

    // Ekstra tett polling — stream kan hoppe over punkter i bakgrunn.
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollPosition());
    });

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onAccel, onError: (_) {});

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onGyro, onError: (_) {});

    _flushTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_flush());
    });

    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      final up = results.any((r) => r != ConnectivityResult.none);
      _online = up;
      if (up) unawaited(_flush());
    });

    _dayTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(DriveMonitorService.archivePreviousDays(companyId));
    });

    _emit();
    unawaited(_flush());
  }

  LocationSettings _androidLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Kjøresporing aktiv',
          notificationText:
              'DriftPro registrerer ruten kontinuerlig (også i bakgrunn).',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );
  }

  Future<void> _pollPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 2),
        ),
      );
      _onPosition(pos);
    } catch (_) {}
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _netSub?.cancel();
    _flushTimer?.cancel();
    _dayTimer?.cancel();
    _pollTimer?.cancel();
    await _flush(force: true);
    await DriveMonitorService.endSession(
      sessionId,
      score: score,
      km: _km,
      eventCount: _eventCount,
      roughEventCount: _roughCount,
      maxSpeedKmh: _maxSpeed,
      avgSpeedKmh: _speedN == 0 ? 0 : _speedSum / _speedN,
    );
    await _queue.clear();
    await WakelockPlus.disable();
    await _statusCtrl.close();
  }

  void _onPosition(Position pos) {
    // Dropp ekstremt dårlige GPS-fiks (unntatt første punkt).
    if (_lastSamplePos != null &&
        pos.accuracy.isFinite &&
        pos.accuracy > 55) {
      return;
    }

    // Filtrer GPS-glitches (teleportering).
    if (_lastSamplePos != null && _lastSampleAt != null) {
      final jump = Geolocator.distanceBetween(
        _lastSamplePos!.latitude,
        _lastSamplePos!.longitude,
        pos.latitude,
        pos.longitude,
      );
      final dt = DateTime.now().difference(_lastSampleAt!).inMilliseconds /
          1000.0;
      if (dt > 0 && dt < 8 && jump / dt > 55) {
        // > ~200 km/t — urealistisk, hopp over.
        return;
      }
    }

    final speed = (pos.speed.isFinite ? pos.speed * 3.6 : 0).clamp(0, 250).toDouble();
    _liveSpeed = speed;
    if (speed > _maxSpeed) _maxSpeed = speed;
    if (speed > 1) {
      _speedSum += speed;
      _speedN++;
    }

    // Hard brake / accel from GPS delta-v.
    if (_lastSpeed != null && _lastPosAt != null) {
      final dt = DateTime.now().difference(_lastPosAt!).inMilliseconds / 1000.0;
      if (dt > 0.35 && dt < 6) {
        final dv = (speed - _lastSpeed!) / 3.6;
        final a = dv / dt;
        if (a <= -hardBrakeMs2) {
          _pushEvent('hard_brake', 'rough', speed, a, pos);
        } else if (a >= hardAccelMs2) {
          _pushEvent('hard_accel', 'warning', speed, a, pos);
        }
      }
    }

    // Sharp turn from heading change.
    if (_lastHeading != null &&
        pos.heading.isFinite &&
        speed >= 18 &&
        _lastPosAt != null) {
      final dt = DateTime.now().difference(_lastPosAt!).inMilliseconds / 1000.0;
      if (dt > 0.2 && dt < 3) {
        var dHead = (pos.heading - _lastHeading!).abs();
        if (dHead > 180) dHead = 360 - dHead;
        final rate = dHead / dt;
        if (dHead >= sharpTurnDeg && rate > 25) {
          _pushEvent('sharp_turn', 'rough', speed, rate, pos, turnRate: rate);
        }
      }
    }

    // Speeding.
    if (speed >= speedingKmh) {
      _pushEvent('speeding', 'warning', speed, 0, pos);
    }

    // Idle.
    if (speed < 3) {
      _idleSince ??= DateTime.now();
      if (DateTime.now().difference(_idleSince!).inMinutes >= 3) {
        _pushEvent('idle', 'info', speed, 0, pos);
        _idleSince = DateTime.now();
      }
    } else {
      _idleSince = null;
    }

    var turnRate = 0.0;
    if (_lastHeading != null && pos.heading.isFinite && _lastPosAt != null) {
      final dt = DateTime.now().difference(_lastPosAt!).inMilliseconds / 1000.0;
      if (dt > 0) {
        var dHead = (pos.heading - _lastHeading!).abs();
        if (dHead > 180) dHead = 360 - dHead;
        turnRate = dHead / dt;
      }
    }

    _lastSpeed = speed;
    _lastPosAt = DateTime.now();
    _lastPos = pos;
    if (pos.heading.isFinite) _lastHeading = pos.heading;

    // Lagre sample: minst hvert 1. sekund ELLER når man har beveget seg ≥1 m.
    final now = DateTime.now();
    var moved = 999.0;
    if (_lastSamplePos != null) {
      moved = Geolocator.distanceBetween(
        _lastSamplePos!.latitude,
        _lastSamplePos!.longitude,
        pos.latitude,
        pos.longitude,
      );
    }
    final elapsedMs = _lastSampleAt == null
        ? 9999
        : now.difference(_lastSampleAt!).inMilliseconds;
    if (moved < 0.8 && elapsedMs < 1000) {
      _emit();
      return;
    }

    if (moved > 0 && moved < 800 && _lastSamplePos != null) {
      _km += moved / 1000.0;
    }

    _lastSampleAt = now;
    _lastSamplePos = pos;
    _sampleBuf.add({
      'company_id': companyId,
      'session_id': sessionId,
      'recorded_at': now.toUtc().toIso8601String(),
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed_kmh': speed,
      'heading_deg': pos.heading.isFinite ? pos.heading : null,
      'accuracy_m': pos.accuracy.isFinite ? pos.accuracy : null,
      'altitude_m': pos.altitude.isFinite ? pos.altitude : null,
      'turn_rate_deg_s': turnRate,
    });
    if (_sampleBuf.length >= 6) unawaited(_flush());
    _emit();
  }

  void _onAccel(AccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final spike = (mag - 9.8).abs();
    if (spike < 4.2) return;
    final now = DateTime.now();
    if (_lastEventAt != null && now.difference(_lastEventAt!).inSeconds < 3) {
      return;
    }
    final severity = spike >= 7 ? 'rough' : 'warning';
    _pushEvent(
      spike >= 7 ? 'hard_brake' : 'hard_accel',
      severity,
      _liveSpeed,
      spike,
      _lastPos,
    );
  }

  void _onGyro(GyroscopeEvent e) {
    // High yaw rate at speed ≈ sharp turn assist.
    final yaw = e.z.abs(); // rad/s
    if (yaw < 1.2 || _liveSpeed < 20) return;
    final now = DateTime.now();
    if (_lastEventAt != null && now.difference(_lastEventAt!).inSeconds < 3) {
      return;
    }
    _pushEvent(
      'sharp_turn',
      yaw >= 2.0 ? 'rough' : 'warning',
      _liveSpeed,
      yaw * 180 / math.pi,
      _lastPos,
      turnRate: yaw * 180 / math.pi,
    );
  }

  void _pushEvent(
    String type,
    String severity,
    double speed,
    double accel,
    Position? pos, {
    double? turnRate,
  }) {
    final now = DateTime.now();
    if (_lastEventAt != null &&
        now.difference(_lastEventAt!).inSeconds < 2 &&
        type == 'speeding') {
      return;
    }
    if (_lastEventAt != null &&
        now.difference(_lastEventAt!).inSeconds < 2 &&
        type == 'idle') {
      return;
    }
    _lastEventAt = now;
    _eventCount++;
    if (severity == 'rough') {
      _roughCount++;
      _liveStatus = 'rough';
    } else if (_liveStatus != 'rough') {
      _liveStatus = 'warning';
    }
    _eventBuf.add({
      'company_id': companyId,
      'session_id': sessionId,
      'recorded_at': now.toUtc().toIso8601String(),
      'event_type': type,
      'severity': severity,
      'speed_kmh': speed,
      'accel_ms2': accel,
      if (pos != null) 'lat': pos.latitude,
      if (pos != null) 'lng': pos.longitude,
      if (turnRate != null) 'note': 'turn_rate=${turnRate.toStringAsFixed(1)}',
    });
    _emit();
    unawaited(_flush());
  }

  Future<void> _flush({bool force = false}) async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Always persist in-memory buffer to disk first (survive kill).
      if (_sampleBuf.isNotEmpty) {
        final copy = List<Map<String, dynamic>>.from(_sampleBuf);
        _sampleBuf.clear();
        await _queue.enqueueSamples(copy);
      }
      if (_eventBuf.isNotEmpty) {
        final copy = List<Map<String, dynamic>>.from(_eventBuf);
        _eventBuf.clear();
        await _queue.enqueueEvents(copy);
      }

      if (!_online && !force) {
        _emit();
        return;
      }

      var (samples, events) = await _queue.peek();
      if (samples.isEmpty && events.isEmpty) {
        // Still update session KPIs when online.
        if (_online) {
          await DriveMonitorService._db.from('drive_monitor_sessions').update({
            'km': _km,
            'event_count': _eventCount,
            'rough_event_count': _roughCount,
            'score': score,
            'max_speed_kmh': _maxSpeed,
            'avg_speed_kmh': _speedN == 0 ? 0 : _speedSum / _speedN,
          }).eq('id', sessionId);
        }
        return;
      }

      // Upload in chunks.
      while (samples.isNotEmpty) {
        final chunk = samples.take(80).toList();
        await DriveMonitorService._db
            .from('drive_monitor_samples')
            .insert(chunk);
        samples = samples.skip(80).toList();
        await _queue.replace(samples: samples, events: events);
      }
      while (events.isNotEmpty) {
        final chunk = events.take(40).toList();
        await DriveMonitorService._db
            .from('drive_monitor_events')
            .insert(chunk);
        events = events.skip(40).toList();
        await _queue.replace(samples: samples, events: events);
      }

      await DriveMonitorService._db.from('drive_monitor_sessions').update({
        'km': _km,
        'event_count': _eventCount,
        'rough_event_count': _roughCount,
        'score': score,
        'max_speed_kmh': _maxSpeed,
        'avg_speed_kmh': _speedN == 0 ? 0 : _speedSum / _speedN,
      }).eq('id', sessionId);

      await _queue.clear();
    } catch (_) {
      // Keep disk queue; retry when connectivity returns.
      _online = false;
    } finally {
      _flushing = false;
      _emit();
    }
  }

  void _emit() {
    if (_statusCtrl.isClosed) return;
    if (_liveStatus != 'ok' &&
        _lastEventAt != null &&
        DateTime.now().difference(_lastEventAt!).inSeconds > 90) {
      _liveStatus = 'ok';
    }
    _statusCtrl.add(DriveMonitorLiveStatus(
      speedKmh: _liveSpeed,
      km: _km,
      score: score,
      status: _liveStatus,
      eventCount: _eventCount,
      roughCount: _roughCount,
      online: _online,
      pendingSamples: _sampleBuf.length,
    ));
  }
}

class DriveMonitorLiveStatus {
  const DriveMonitorLiveStatus({
    required this.speedKmh,
    required this.km,
    required this.score,
    required this.status,
    required this.eventCount,
    required this.roughCount,
    this.online = true,
    this.pendingSamples = 0,
  });

  final double speedKmh;
  final double km;
  final double score;
  final String status;
  final int eventCount;
  final int roughCount;
  final bool online;
  final int pendingSamples;
}
