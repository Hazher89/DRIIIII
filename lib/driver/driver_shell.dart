import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/driftpro_client.dart';
import '../last_mile/models/lm_route.dart';
import '../last_mile/services/last_mile_route_service.dart';
import '../last_mile/services/lm_gps_service.dart';
import '../models/user_profile.dart';
import 'screens/driver_route_screen.dart';
import 'screens/driver_scan_screen.dart';

enum _DriverTab { route, scan }

class DriverShell extends StatefulWidget {
  final UserProfile profile;

  const DriverShell({super.key, required this.profile});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  _DriverTab _tab = _DriverTab.route;
  List<LmRoute> _routes = [];
  LmRoute? _active;
  Timer? _gpsTimer;
  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    var routes = await LastMileRouteService.fetchDriverRoutes(widget.profile.id, day);

    final vid = widget.profile.partnerVehicleId;
    if (vid != null) {
      routes = routes.where((r) => r.partnerVehicleId == vid).toList();
    }

    if (mounted) {
      setState(() {
        _routes = routes;
        _active = routes.isNotEmpty ? routes.first : null;
      });
    }
  }

  Future<void> _startGps() async {
    if (_active == null) return;
    final ok = await LmGpsService.ensurePermission();
    if (!ok) return;

    await LastMileRouteService.startRoute(_active!.id, widget.profile.id);
    await _pingGps();

    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pingGps());

    setState(() => _tracking = true);
  }

  Future<void> _pingGps() async {
    if (_active == null) return;
    await LmGpsService.uploadPosition(
      partnerVehicleId: _active!.partnerVehicleId,
      routeId: _active!.id,
      driverProfileId: widget.profile.id,
    );
  }

  Future<void> _signOut() async {
    _gpsTimer?.cancel();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${DriftProClient.displayName} Sjåfør'),
        actions: [
          if (_tracking)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.gps_fixed, color: Colors.green),
            ),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _tab == _DriverTab.route
          ? DriverRouteScreen(
              routes: _routes,
              active: _active,
              onSelect: (r) => setState(() => _active = r),
              onStartGps: _startGps,
              onRefresh: _loadRoutes,
              tracking: _tracking,
            )
          : const DriverScanScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => setState(() => _tab = _DriverTab.values[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route), label: 'Rute'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Lager'),
        ],
      ),
    );
  }
}
