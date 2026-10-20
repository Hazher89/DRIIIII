import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../owner_portal/owner_portal_route_history.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_portal_route_list_tile.dart';
import '../widgets/partner_ui.dart';
import 'driver_portal_common.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class DriverPortalRoutesPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const DriverPortalRoutesPage({super.key, required this.partner, required this.profile});

  @override
  State<DriverPortalRoutesPage> createState() => _DriverPortalRoutesPageState();
}

class _DriverPortalRoutesPageState extends State<DriverPortalRoutesPage> {
  int _tab = 0;
  DriverPortalData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    final d = await DriverPortalData.load(
      partner: widget.partner,
      partnerVehicleId: widget.profile.partnerVehicleId,
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _data = d;
        _loading = false;
      });
    }
  }

  Future<void> _reload() => _load(forceRefresh: true);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);
    final pending = _data?.pendingAck ?? 0;
    final muted = PartnerUi.mutedText(context);

    return PartnerPortalPageShell(
      backgroundColor: surface,
      title: 'Mine ruter',
      body: _loading || _data == null
          ? const DriftProLoadingCenter()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending > 0)
                  Material(
                    color: Colors.orange.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.mark_email_unread, color: Colors.orange.shade900, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$pending nye ruter — trykk på en rute for å åpne, se PDF og akseptere',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text('Kommende (${_data!.routesKommende.length})'),
                        icon: Icon(
                          pending > 0 ? Icons.mark_email_unread : Icons.route_outlined,
                          size: 18,
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Tidligere (${_data!.routesArchive.length})'),
                        icon: const Icon(Icons.history, size: 18),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                if (_tab == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text(
                      'Her ligger både nye ruter og aksepterte ruter for i dag og fremover.',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
                    ),
                  ),
                Expanded(
                  child: switch (_tab) {
                    0 => _groupedList(
                        _data!.routesKommende,
                        OwnerRouteHistorySort.dateAsc,
                        'Ingen kommende ruter. Du får varsel når noe tildeles.',
                        upcoming: true,
                      ),
                    _ => _groupedList(
                        _data!.routesArchive,
                        OwnerRouteHistorySort.dateDesc,
                        'Ingen tidligere ruter ennå.',
                        upcoming: false,
                      ),
                  },
                ),
              ],
            ),
    );
  }

  Widget _groupedList(
    List<PartnerRouteShare> routes,
    OwnerRouteHistorySort sort,
    String empty, {
    required bool upcoming,
  }) {
    if (routes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(empty, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      );
    }

    final buckets = buildOwnerDayBuckets(routes, sort);
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return RefreshIndicator(
      onRefresh: _reload,
      color: DriftProTheme.primaryGreen,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        itemCount: buckets.length,
        itemBuilder: (_, i) {
          final b = buckets[i];
          final day = b.day;
          final String dayLabel;
          if (upcoming && day == today) {
            dayLabel = 'I dag · ${DateFormat('d. MMM', 'nb').format(day)}';
          } else if (upcoming && day == today.add(const Duration(days: 1))) {
            dayLabel = 'I morgen · ${DateFormat('d. MMM', 'nb').format(day)}';
          } else if (!upcoming && day == today.subtract(const Duration(days: 1))) {
            dayLabel = 'I går · ${DateFormat('d. MMM', 'nb').format(day)}';
          } else {
            dayLabel = DateFormat('EEEE d. MMMM', 'nb').format(day);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                  child: Text(
                    dayLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                for (final route in b.routes)
                  PartnerPortalRouteListTile(
                    route: route,
                    shifts: _data!.shiftsById,
                    onReload: _reload,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
