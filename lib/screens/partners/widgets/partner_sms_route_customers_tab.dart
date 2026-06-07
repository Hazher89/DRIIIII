import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nb_date_format.dart';
import 'partner_sms_message_section.dart';
import 'partner_ui.dart';

/// Velg dato + sjåfør, les kunder fra rute-PDF, velg mottakere, mal og send SMS.
class PartnerSmsRouteCustomersTab extends StatefulWidget {
  final String companyId;
  final List<FleetPartnerVehicleRow> fleet;
  final TextEditingController messageCtrl;
  final bool sending;
  final Future<void> Function(List<RoutePdfCustomer> customers) onSend;
  final bool scrollable;

  const PartnerSmsRouteCustomersTab({
    super.key,
    required this.companyId,
    required this.fleet,
    required this.messageCtrl,
    required this.sending,
    required this.onSend,
    this.scrollable = false,
  });

  @override
  State<PartnerSmsRouteCustomersTab> createState() => _PartnerSmsRouteCustomersTabState();
}

class _PartnerSmsRouteCustomersTabState extends State<PartnerSmsRouteCustomersTab> {
  static const _stepSelect = 0;
  static const _stepCompose = 1;

  int _step = _stepSelect;
  late DateTime _day;
  String? _vehicleId;
  List<RoutePdfCustomer> _customers = [];
  final Set<String> _selectedKeys = {};
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
    widget.messageCtrl.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    widget.messageCtrl.removeListener(_onMessageChanged);
    super.dispose();
  }

  void _onMessageChanged() {
    if (mounted) setState(() {});
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

  List<RoutePdfCustomer> get _selectedCustomers =>
      _customers.where((c) => _selectedKeys.contains(c.phoneNormalizedKey)).toList();

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
      _selectedKeys.clear();
      _routeTitle = null;
      _step = _stepSelect;
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
                'Sjekk at ruten har PDF lastet opp for valgt dag og MAVI.';
          }
        });
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
    setState(() {
      if (select) {
        for (final c in _customers) {
          _selectedKeys.add(c.phoneNormalizedKey);
        }
      } else {
        _selectedKeys.clear();
      }
    });
  }

  void _toggleOne(RoutePdfCustomer c, bool selected) {
    setState(() {
      if (selected) {
        _selectedKeys.add(c.phoneNormalizedKey);
      } else {
        _selectedKeys.remove(c.phoneNormalizedKey);
      }
    });
  }

  void _goToCompose() {
    if (_selectedCustomers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én kunde')),
      );
      return;
    }
    setState(() => _step = _stepCompose);
  }

  Future<void> _confirmAndSend() async {
    final selected = _selectedCustomers;
    final msg = widget.messageCtrl.text.trim();
    if (selected.isEmpty || msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg kunder og skriv melding')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send SMS til ${selected.length} kunde${selected.length == 1 ? '' : 'r'}?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Melding:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              Text(msg, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              const Text('Mottakere:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              ...selected.take(8).map(
                    (c) => Text(
                      '• ${c.sequence}. ${c.name} (${c.phoneDisplay})'
                      '${c.deliveryWindow != null ? ' · ${c.deliveryWindow}' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              if (selected.length > 8) Text('… og ${selected.length - 8} til', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            child: const Text('Bekreft og send'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    await widget.onSend(selected);
    if (mounted) {
      setState(() {
        _step = _stepSelect;
        _selectedKeys.clear();
      });
    }
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

    if (_step == _stepCompose) {
      return _buildComposeStep(context);
    }
    return _buildSelectStep(context);
  }

  Widget _buildSelectStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = _selectedCustomers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Hent kunder fra MAVI-rute-PDF. Velg dato og sjåfør, marker kundene du vil sende SMS til, '
            'og trykk «Gå videre» for å velge mal og sende.',
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
                label: const Text('Hent kunder'),
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
                        MaviUnitCodes.fleetDriverLabel(
                          row.vehicle.unitCode,
                          row.vehicle.driverName ?? row.partner.name,
                        ),
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
                '$selectedCount valgt',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PartnerUi.mutedText(context)),
              ),
            ],
          ),
        ),
        _buildCustomerList(context, isDark),
        if (!widget.scrollable)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: selectedCount == 0 ? null : _goToCompose,
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.arrow_forward),
                label: Text('Gå videre til melding ($selectedCount)'),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: selectedCount == 0 ? null : _goToCompose,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: Text('Gå videre til melding ($selectedCount)'),
            ),
          ),
      ],
    );
  }

  Widget _buildCustomerList(BuildContext context, bool isDark) {
    if (widget.scrollable) {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen)),
        );
      }
      if (_customers.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Trykk «Hent kunder» for å lese telefonnummer fra rute-PDF.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PartnerUi.mutedText(context)),
          ),
        );
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: _customers.length,
        itemBuilder: (_, i) => _customerTile(_customers[i]),
      );
    }

    return Expanded(
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen))
          : _customers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Trykk «Hent kunder» for å lese telefonnummer fra rute-PDF.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: PartnerUi.mutedText(context)),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: _customers.length,
                  itemBuilder: (_, i) => _customerTile(_customers[i]),
                ),
    );
  }

  Widget _customerTile(RoutePdfCustomer c) {
    final selected = _selectedKeys.contains(c.phoneNormalizedKey);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Checkbox(
          value: selected,
          activeColor: DriftProTheme.primaryGreen,
          onChanged: (v) => _toggleOne(c, v == true),
        ),
        title: Text(
          '${c.sequence}. ${c.name}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: _customerSubtitle(c),
        isThreeLine: c.deliveryWindow != null,
        onTap: () => _toggleOne(c, !selected),
      ),
    );
  }

  Widget _customerSubtitle(RoutePdfCustomer c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.phoneDisplay,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        if (c.deliveryWindow != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Levering: ${c.deliveryWindow}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DriftProTheme.accentBlue,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildComposeStep(BuildContext context) {
    final selected = _selectedCustomers;
    final msgEmpty = widget.messageCtrl.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.sending ? null : () => setState(() => _step = _stepSelect),
              ),
              Expanded(
                child: Text(
                  'Send SMS til ${selected.length} kunde${selected.length == 1 ? '' : 'r'}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        if (widget.scrollable)
          ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mottakere', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ...selected.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${c.sequence}. ${c.name} · ${c.phoneDisplay}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PartnerSmsMessageSection(
                messageCtrl: widget.messageCtrl,
                onChanged: () => setState(() {}),
              ),
            ],
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mottakere', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        ...selected.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${c.sequence}. ${c.name} · ${c.phoneDisplay}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PartnerSmsMessageSection(
                  messageCtrl: widget.messageCtrl,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
        if (widget.scrollable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.sending ? null : () => setState(() => _step = _stepSelect),
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Endre kundevalg'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.sending || msgEmpty ? null : _confirmAndSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: widget.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: Text('Send SMS og bekreft (${selected.length})'),
                ),
              ],
            ),
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.sending ? null : () => setState(() => _step = _stepSelect),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Endre kundevalg'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: widget.sending || msgEmpty ? null : _confirmAndSend,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: widget.sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text('Send SMS og bekreft (${selected.length})'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
