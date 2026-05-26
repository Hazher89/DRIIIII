import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/vehicle_rental_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/partner/vehicle_rental.dart';
import 'widgets/vehicle_rental_ui.dart';

/// MAVI: opprett utleie, godkjenn, retur, søk i arkiv.
class VehicleRentalHubScreen extends StatefulWidget {
  final bool embedded;
  final List<Partner> partners;

  const VehicleRentalHubScreen({
    super.key,
    this.embedded = false,
    required this.partners,
  });

  @override
  State<VehicleRentalHubScreen> createState() => _VehicleRentalHubScreenState();
}

class _VehicleRentalHubScreenState extends State<VehicleRentalHubScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  String? _statusFilter;
  List<VehicleRental> _rentals = [];
  Map<String, List<PartnerVehicle>> _vehiclesByPartner = {};
  Set<String> _blockedVehicleIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final fleet = await PartnerService.fetchCompanyFleet(cid);
      final byPartner = <String, List<PartnerVehicle>>{};
      for (final row in fleet) {
        byPartner.putIfAbsent(row.partner.id, () => []).add(row.vehicle);
      }
      final blocked = await VehicleRentalService.fetchBlockedVehicleIds(cid);
      final rentals = await VehicleRentalService.fetchForCompany(
        cid,
        query: _search.text,
        statusFilter: _statusFilter,
      );
      if (mounted) {
        setState(() {
          _vehiclesByPartner = byPartner;
          _blockedVehicleIds = blocked;
          _rentals = rentals;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreateSheet() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null || !mounted) return;

    String? lenderId;
    String? borrowerId;
    String? vehicleId;
    DateTime? start;
    DateTime? end;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final lenderVehicles = lenderId == null
              ? const <PartnerVehicle>[]
              : (_vehiclesByPartner[lenderId] ?? [])
                  .where((v) => v.vehicleKind == 'mavi')
                  .where((v) => !_blockedVehicleIds.contains(v.id))
                  .toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ny bilutleie', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: lenderId,
                    decoration: const InputDecoration(labelText: 'Utleier (bil-eier)'),
                    isExpanded: true,
                    items: widget.partners
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setDlg(() {
                      lenderId = v;
                      vehicleId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: vehicleId,
                    decoration: InputDecoration(
                      labelText: 'MAVI-bil',
                      helperText: lenderVehicles.isEmpty && lenderId != null
                          ? 'Alle biler er blokkert eller utlånt'
                          : null,
                    ),
                    isExpanded: true,
                    items: lenderVehicles
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text('${MaviUnitCodes.normalize(v.unitCode)} · ${v.registrationNumber}'),
                          ),
                        )
                        .toList(),
                    onChanged: lenderVehicles.isEmpty ? null : (v) => setDlg(() => vehicleId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: borrowerId,
                    decoration: const InputDecoration(labelText: 'Låntaker'),
                    isExpanded: true,
                    items: widget.partners
                        .where((p) => p.id != lenderId)
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setDlg(() => borrowerId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 1)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (d != null) setDlg(() => start = d);
                          },
                          icon: const Icon(Icons.event, size: 18),
                          label: Text(start == null ? 'Start' : DateFormat('d.M.y').format(start!)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: start ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 1)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (d != null) setDlg(() => end = d);
                          },
                          icon: const Icon(Icons.event, size: 18),
                          label: Text(end == null ? 'Slutt' : DateFormat('d.M.y').format(end!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: lenderId != null && borrowerId != null && vehicleId != null
                        ? () => Navigator.pop(ctx, true)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text('Opprett og send SMS til bileier'),
                  ),
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (ok != true || lenderId == null || borrowerId == null || vehicleId == null) return;

    PartnerVehicle? vehicle;
    for (final list in _vehiclesByPartner.values) {
      for (final v in list) {
        if (v.id == vehicleId) {
          vehicle = v;
          break;
        }
      }
    }
    if (vehicle == null) return;

    try {
      await VehicleRentalService.createRental(
        companyId: cid,
        lenderPartnerId: lenderId!,
        borrowerPartnerId: borrowerId!,
        vehicle: vehicle,
        rentalStart: start,
        rentalEnd: end,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utleie opprettet — bileier varslet på SMS')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _askMaviComment({required String title, required String hint}) async {
    final ctrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                labelText: 'MAVI-kommentar (valgfritt, arkiveres)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
              child: const Text('Fortsett'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _approveCheckout(VehicleRental rental) async {
    final comment = await _askMaviComment(
      title: 'Godkjenn utleie',
      hint: 'F.eks. nøkkel klar, avtalt periode bekreftet…',
    );
    if (!mounted) return;
    if (comment == null) return;

    await VehicleRentalService.approveCheckout(rental.id, maviComment: comment.isEmpty ? null : comment);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utleie godkjent — bil blokkert til retur')),
      );
      await _load();
    }
  }

  Future<void> _approveReturn(VehicleRental rental) async {
    final comment = await _askMaviComment(
      title: 'Godkjenn retur',
      hint: 'F.eks. bil mottatt, skader notert…',
    );
    if (!mounted) return;
    if (comment == null) return;

    await VehicleRentalService.approveReturn(rental.id, maviComment: comment.isEmpty ? null : comment);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retur godkjent — bil tilgjengelig igjen')),
      );
      await _load();
    }
  }

  Future<void> _reject(VehicleRental rental) async {
    final reason = await _askMaviComment(
      title: 'Avvis',
      hint: 'Årsak til avvisning…',
    );
    if (!mounted) return;
    if (reason == null) return;
    await VehicleRentalService.reject(rental.id, reason: reason.isEmpty ? null : reason);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avvist')));
      await _load();
    }
  }

  Future<void> _showDetail(VehicleRental rental) async {
    await showVehicleRentalDetailSheet(
      context,
      rental: rental,
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rental.isPendingMavi) ...[
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _approveCheckout(rental);
              },
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
              icon: const Icon(Icons.check),
              label: const Text('Godkjenn utleie'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _reject(rental);
              },
              icon: const Icon(Icons.close),
              label: const Text('Avvis'),
            ),
          ],
          if (rental.isPendingReturnMavi) ...[
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _approveReturn(rental);
              },
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.success),
              icon: const Icon(Icons.assignment_return),
              label: const Text('Godkjenn retur'),
            ),
          ],
        ],
      ),
    );
  }

  List<VehicleRental> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rentals;
    return _rentals.where((r) {
      return (r.registrationNumber ?? '').toLowerCase().contains(q) ||
          (r.unitCode ?? '').toLowerCase().contains(q) ||
          (r.borrowerPartnerName ?? '').toLowerCase().contains(q) ||
          (r.lenderPartnerName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  int _count(String status) => _rentals.where((r) => r.status == status).length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Søk reg.nr, MAVI, bedrift…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  isDense: true,
                  suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            const SizedBox(height: 10),
            VehicleRentalStatsRow(
              pendingOwner: _count('pending_owner'),
              pendingMavi: _count('pending_mavi'),
              onLoan: _count('approved'),
              pendingReturn: _count('pending_return_mavi'),
              returned: _count('returned'),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Alle',
                    selected: _statusFilter == null,
                    onTap: () {
                      setState(() => _statusFilter = null);
                      _load();
                    },
                  ),
                  _FilterChip(
                    label: 'MAVI utleie',
                    selected: _statusFilter == 'pending_mavi',
                    count: _count('pending_mavi'),
                    onTap: () {
                      setState(() => _statusFilter = 'pending_mavi');
                      _load();
                    },
                  ),
                  _FilterChip(
                    label: 'Utleid',
                    selected: _statusFilter == 'approved',
                    count: _count('approved'),
                    onTap: () {
                      setState(() => _statusFilter = 'approved');
                      _load();
                    },
                  ),
                  _FilterChip(
                    label: 'Retur',
                    selected: _statusFilter == 'pending_return_mavi',
                    count: _count('pending_return_mavi'),
                    onTap: () {
                      setState(() => _statusFilter = 'pending_return_mavi');
                      _load();
                    },
                  ),
                  _FilterChip(
                    label: 'Arkiv',
                    selected: _statusFilter == 'returned',
                    onTap: () {
                      setState(() => _statusFilter = 'returned');
                      _load();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Ingen utleier.\nTrykk + for ny utleie.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) {
                                  final r = _filtered[i];
                                  return VehicleRentalMobileCard(
                                    rental: r,
                                    onTap: () => _showDetail(r),
                                    action: _buildCardAction(r),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _openCreateSheet,
            backgroundColor: DriftProTheme.primaryGreen,
            icon: const Icon(Icons.add),
            label: const Text('Ny utleie'),
          ),
        ),
      ],
    );
  }

  Widget? _buildCardAction(VehicleRental r) {
    if (r.isPendingMavi) {
      return FilledButton.icon(
        onPressed: () => _approveCheckout(r),
        style: FilledButton.styleFrom(
          backgroundColor: DriftProTheme.primaryGreen,
          minimumSize: const Size(double.infinity, 44),
        ),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Godkjenn utleie'),
      );
    }
    if (r.isPendingReturnMavi) {
      return FilledButton.icon(
        onPressed: () => _approveReturn(r),
        style: FilledButton.styleFrom(
          backgroundColor: DriftProTheme.success,
          minimumSize: const Size(double.infinity, 44),
        ),
        icon: const Icon(Icons.assignment_return, size: 18),
        label: const Text('Godkjenn retur'),
      );
    }
    return null;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = count != null && count! > 0 ? '$label ($count)' : label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(text, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
