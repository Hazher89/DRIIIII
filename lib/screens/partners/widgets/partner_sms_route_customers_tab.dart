import 'package:flutter/material.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nb_date_format.dart';
import 'partner_ui.dart';

/// Velg dato + sjåfør, les kunder fra rute-PDF, velg mottakere til SMS.
class PartnerSmsRouteCustomersTab extends StatefulWidget {
  final String companyId;
  final List<FleetPartnerVehicleRow> fleet;
  final Set<String> selectedPhoneKeys;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<List<RoutePdfCustomer>>? onCustomersLoaded;

  const PartnerSmsRouteCustomersTab({
    super.key,
    required this.companyId,
    required this.fleet,
    required this.selectedPhoneKeys,
    required this.onSelectionChanged,
    this.onCustomersLoaded,
  });

  @override
  State<PartnerSmsRouteCustomersTab> createState() => _PartnerSmsRouteCustomersTabState();
}

class _PartnerSmsRouteCustomersTabState extends State<PartnerSmsRouteCustomersTab> {
  late DateTime _day;
  String? _vehicleId;
  List<RoutePdfCustomer> _customers = [];
  bool _loading = false;
  String? _error;
  String? _routeTitle;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now();
    if (widget.fleet.isNotEmpty) {
      _vehicleId = widget.fleet.first.vehicle.id;
    }
  }

  List<FleetPartnerVehicleRow> get _sortedFleet {
    final copy = [...widget.fleet];
    copy.sort((a, b) {
      final c = a.vehicle.unitCode.compareTo(b.vehicle.unitCode);
      if (c != 0) return c;
      return (a.vehicle.driverName ?? '').compareTo(b.vehicle.driverName ?? '');
    });
    return copy;
  }

  Future<void> _loadCustomers() async {
    final vid = _vehicleId;
    if (vid == null) {
      setState(() => _error = 'Velg sjåfør / MAVI-enhet.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _customers = [];
      _routeTitle = null;
    });
    try {
      final list = await PartnerService.fetchRouteCustomersForVehicleDay(
        companyId: widget.companyId,
        partnerVehicleId: vid,
        day: _day,
      );
      FleetPartnerVehicleRow? row;
      for (final r in widget.fleet) {
        if (r.vehicle.id == vid) {
          row = r;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _customers = list;
          _loading = false;
          _routeTitle = row != null
              ? '${row.vehicle.unitCode}${row.vehicle.driverName != null && row.vehicle.driverName!.trim().isNotEmpty ? ' · ${row.vehicle.driverName}' : ''}'
              : null;
          if (list.isEmpty) {
            _error =
                'Ingen kunder funnet for ${NbDateFormat.format(_day, 'd. MMM yyyy')}. '
                'Sjekk at ruten er sendt til sjåfør og at PDF er lastet opp.';
          }
        });
        widget.onCustomersLoaded?.call(list);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _toggleAll(bool select) {
    final next = <String>{...widget.selectedPhoneKeys};
    if (select) {
      for (final c in _customers) {
        next.add(c.phoneNormalizedKey);
      }
    } else {
      for (final c in _customers) {
        next.remove(c.phoneNormalizedKey);
      }
    }
    widget.onSelectionChanged(next);
  }

  void _toggleOne(RoutePdfCustomer c, bool? value) {
    final next = <String>{...widget.selectedPhoneKeys};
    if (value == true) {
      next.add(c.phoneNormalizedKey);
    } else {
      next.remove(c.phoneNormalizedKey);
    }
    widget.onSelectionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fleet.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Ingen sjåfører/MAVI-enheter registrert i flåten.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PartnerUi.mutedText(context)),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedOnPage =
        _customers.where((c) => widget.selectedPhoneKeys.contains(c.phoneNormalizedKey)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Hent kunder fra MAVI-rute-PDF (Trip Overview). Velg dato og sjåfør, '
            'deretter én eller flere kunder til SMS på «Send SMS»-fanen.',
            style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context), height: 1.35),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _day,
                            firstDate: DateTime.now().subtract(const Duration(days: 90)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) setState(() => _day = d);
                        },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(NbDateFormat.format(_day, 'd. MMM yyyy')),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading || _vehicleId == null ? null : _loadCustomers,
                style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Hent'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Sjåfør / MAVI-enhet',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _vehicleId,
                isExpanded: true,
                items: [
                  for (final row in _sortedFleet)
                    DropdownMenuItem(
                      value: row.vehicle.id,
                      child: Text(
                        '${row.vehicle.unitCode}'
                        '${row.vehicle.driverName != null && row.vehicle.driverName!.trim().isNotEmpty ? ' · ${row.vehicle.driverName}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _vehicleId = v),
              ),
            ),
          ),
        ),
        if (_routeTitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Rute: $_routeTitle · ${_customers.length} kunder',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(_error!, style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _customers.isEmpty ? null : () => _toggleAll(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Velg alle'),
              ),
              TextButton.icon(
                onPressed: _customers.isEmpty ? null : () => _toggleAll(false),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('Fjern valg'),
              ),
              const Spacer(),
              Text(
                '$selectedOnPage valgt',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PartnerUi.mutedText(context)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen))
              : _customers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Trykk «Hent» for å lese kunder fra rute-PDF.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PartnerUi.mutedText(context)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: _customers.length,
                      itemBuilder: (_, i) {
                        final c = _customers[i];
                        final selected = widget.selectedPhoneKeys.contains(c.phoneNormalizedKey);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: Checkbox(
                              value: selected,
                              activeColor: DriftProTheme.primaryGreen,
                              onChanged: (v) => _toggleOne(c, v),
                            ),
                            title: Text(
                              '${c.sequence}. ${c.name}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${c.phoneDisplay}'
                              '${c.addressHint != null ? '\n${c.addressHint!.length > 60 ? '${c.addressHint!.substring(0, 60)}…' : c.addressHint}' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            isThreeLine: c.addressHint != null,
                            onTap: () => _toggleOne(c, !selected),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
