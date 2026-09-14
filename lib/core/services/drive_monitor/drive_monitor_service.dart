import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../native_permissions_service.dart';
import '../supabase_service.dart';

/// Leiebil-sporing: GPS + akselerometer → sessions/events i Supabase.
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
        .select('id, full_name, employee_number, email, drive_monitor_device')
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
        .select('id, full_name, employee_number, email, drive_monitor_device')
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

  static Future<void> setDeviceUser(String profileId, bool enabled) async {
    await _db.from('profiles').update({
      'drive_monitor_device': enabled,
    }).eq('id', profileId);
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
      // Første gang: godta 0000 som midlertidig PIN.
      return pin.trim() == '0000';
    }
    return hash == hashPin(pin);
  }

  static Future<List<Map<String, dynamic>>> listSessions({
    required String companyId,
    int limit = 80,
  }) async {
    final rows = await _db
        .from('drive_monitor_sessions')
        .select()
        .eq('company_id', companyId)
        .order('started_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> listEvents({
    required String companyId,
    String? sessionId,
    int limit = 100,
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
    }).select('id').single();
    return row['id'] as String;
  }

  static Future<void> endSession(
    String sessionId, {
    required double score,
    required double km,
    required int eventCount,
    required int roughEventCount,
  }) async {
    await _db.from('drive_monitor_sessions').update({
      'status': 'ended',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'score': score,
      'km': km,
      'event_count': eventCount,
      'rough_event_count': roughEventCount,
    }).eq('id', sessionId);
  }
}

/// Live tracking-motor for én leiebil (kiosk).
class DriveMonitorTracker {
  DriveMonitorTracker({
    required this.companyId,
    required this.sessionId,
    this.hardBrakeMs2 = 3.5,
    this.hardAccelMs2 = 3.0,
  });

  final String companyId;
  final String sessionId;
  final double hardBrakeMs2;
  final double hardAccelMs2;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _flushTimer;

  double? _lastSpeed;
  DateTime? _lastPosAt;
  Position? _lastPos;
  double _km = 0;
  int _eventCount = 0;
  int _roughCount = 0;
  double _liveSpeed = 0;
  String _liveStatus = 'ok'; // ok | warning | rough
  DateTime? _lastEventAt;

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
    await NativePermissionsService.ensureLocation();
    await WakelockPlus.enable();

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition);

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onAccel);

    _flushTimer = Timer.periodic(const Duration(seconds: 8), (_) => _flush());
    _emit();
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    await _accelSub?.cancel();
    _flushTimer?.cancel();
    await _flush();
    await DriveMonitorService.endSession(
      sessionId,
      score: score,
      km: _km,
      eventCount: _eventCount,
      roughEventCount: _roughCount,
    );
    await WakelockPlus.disable();
    await _statusCtrl.close();
  }

  void _onPosition(Position pos) {
    final speed = (pos.speed * 3.6).clamp(0, 200).toDouble();
    _liveSpeed = speed;
    if (_lastPos != null) {
      final d = Geolocator.distanceBetween(
        _lastPos!.latitude,
        _lastPos!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (d > 0 && d < 500) _km += d / 1000.0;
    }

    if (_lastSpeed != null && _lastPosAt != null) {
      final dt = DateTime.now().difference(_lastPosAt!).inMilliseconds / 1000.0;
      if (dt > 0.4 && dt < 8) {
        final dv = (speed - _lastSpeed!) / 3.6; // m/s
        final a = dv / dt;
        if (a <= -hardBrakeMs2) {
          _pushEvent('hard_brake', 'rough', speed, a, pos);
        } else if (a >= hardAccelMs2) {
          _pushEvent('hard_accel', 'warning', speed, a, pos);
        }
      }
    }

    _lastSpeed = speed;
    _lastPosAt = DateTime.now();
    _lastPos = pos;

    _sampleBuf.add({
      'company_id': companyId,
      'session_id': sessionId,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed_kmh': speed,
      'heading_deg': pos.heading,
    });
    if (_sampleBuf.length >= 12) unawaited(_flush());
    _emit();
  }

  void _onAccel(AccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    // Gravity ~9.8; spikes above that indicate jolts.
    final spike = (mag - 9.8).abs();
    if (spike < 4.5) return;
    final now = DateTime.now();
    if (_lastEventAt != null && now.difference(_lastEventAt!).inSeconds < 4) {
      return;
    }
    final pos = _lastPos;
    final severity = spike >= 7 ? 'rough' : 'warning';
    _pushEvent(
      spike >= 7 ? 'hard_brake' : 'hard_accel',
      severity,
      _liveSpeed,
      spike,
      pos,
    );
  }

  void _pushEvent(
    String type,
    String severity,
    double speed,
    double accel,
    Position? pos,
  ) {
    _lastEventAt = DateTime.now();
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
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'event_type': type,
      'severity': severity,
      'speed_kmh': speed,
      'accel_ms2': accel,
      if (pos != null) 'lat': pos.latitude,
      if (pos != null) 'lng': pos.longitude,
    });
    _emit();
    unawaited(_flush());
  }

  Future<void> _flush() async {
    try {
      if (_sampleBuf.isNotEmpty) {
        final batch = List<Map<String, dynamic>>.from(_sampleBuf);
        _sampleBuf.clear();
        await DriveMonitorService._db.from('drive_monitor_samples').insert(batch);
      }
      if (_eventBuf.isNotEmpty) {
        final batch = List<Map<String, dynamic>>.from(_eventBuf);
        _eventBuf.clear();
        await DriveMonitorService._db.from('drive_monitor_events').insert(batch);
      }
      await DriveMonitorService._db.from('drive_monitor_sessions').update({
        'km': _km,
        'event_count': _eventCount,
        'rough_event_count': _roughCount,
        'score': score,
      }).eq('id', sessionId);
    } catch (_) {
      // Keep buffering on transient network errors.
    }
  }

  void _emit() {
    if (_statusCtrl.isClosed) return;
    // Soften status back to ok after quiet period.
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
  });

  final double speedKmh;
  final double km;
  final double score;
  final String status;
  final int eventCount;
  final int roughCount;
}
