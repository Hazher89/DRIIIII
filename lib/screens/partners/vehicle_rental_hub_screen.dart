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
import 'widgets/partner_modern_ui.dart';
import 'widgets/vehicle_rental_ui.dart';

/// MAVI: opprett utleie, godkjenn, retur, søk i arkiv.
class VehicleRentalHubScreen extends StatefulWidget {
  final bool embedded;
  final bool nestedScroll;
  final List<Partner> partners;
  final bool canApproveRentals;
  final bool canForceDeleteRentals;

  const VehicleRentalHubScreen({
    super.key,
    this.embedded = false,
    this.nestedScroll = false,
    required this.partners,
    this.canApproveRentals = false,
    this.canForceDeleteRentals = false,
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

  String _formatTime24(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

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

    Partner? maviPartner;
    for (final p in widget.partners) {
      if (p.isActive && p.name.trim().toLowerCase().startsWith('mavi logistikk')) {
        maviPartner = p;
        break;
      }
    }
    if (maviPartner == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fant ikke aktiv bedrift «MAVI Logistikk AS». Aktiver/opprett denne først.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final String lenderId = maviPartner.id;
    String? borrowerId;
    String? vehicleId;
    DateTime? start;
    DateTime? end;
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final allBorrowerVehicles =
              borrowerId == null ? const <PartnerVehicle>[] : (_vehiclesByPartner[borrowerId] ?? []);
          final borrowerVehicles =
              allBorrowerVehicles.where((v) => !_blockedVehicleIds.contains(v.id)).toList();
          final blockedBorrowerVehicles =
              allBorrowerVehicles.where((v) => _blockedVehicleIds.contains(v.id)).toList();
          final selectedBorrowerVehicleStillExists =
              vehicleId != null && borrowerVehicles.any((v) => v.id == vehicleId);
          if (!selectedBorrowerVehicleStillExists) {
            vehicleId = null;
          }
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
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Utleier (alltid)',
                      border: OutlineInputBorder(),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.business, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'MAVI Logistikk AS',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: borrowerId,
                    decoration: const InputDecoration(labelText: 'Låntaker (bedrift som skal få leiebil)'),
                    isExpanded: true,
                    items: widget.partners
                        .where((p) => p.id != lenderId)
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setDlg(() => borrowerId = v),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: borrowerId == null
                        ? const Text(
                            'Velg låntaker for å velge bil.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Velg bil registrert på valgt bedrift',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: vehicleId,
                                decoration: InputDecoration(
                                  labelText: 'Bedriftens bil',
                                  helperText: borrowerVehicles.isEmpty
                                      ? 'Ingen tilgjengelige biler (kan være blokkert/utlånt)'
                                      : null,
                                ),
                                isExpanded: true,
                                items: borrowerVehicles
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v.id,
                                        child: Text(
                                          '${MaviUnitCodes.normalize(v.unitCode)} · ${v.registrationNumber}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: borrowerVehicles.isEmpty
                                    ? null
                                    : (v) => setDlg(() => vehicleId = v),
                              ),
                              if (blockedBorrowerVehicles.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Disse bilene er allerede utlånt/blokkert:',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 6),
                                      ...blockedBorrowerVehicles.map((vehicle) {
                                        VehicleRental? activeRental;
                                        for (final r in _rentals) {
                                          if (r.partnerVehicleId == vehicle.id &&
                                              VehicleRentalService.activeStatuses.contains(r.status)) {
                                            activeRental = r;
                                            break;
                                          }
                                        }
                                        final holder = activeRental?.borrowerPartnerName ?? 'ukjent låntaker';
                                        final until = activeRental?.rentalEndAt;
                                        final untilLabel = until == null
                                            ? 'ukjent slutttid'
                                            : DateFormat('d.M.y HH:mm', 'nb').format(until.toLocal());
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            '• ${MaviUnitCodes.normalize(vehicle.unitCode)} · ${vehicle.registrationNumber} '
                                            '— har bilen: $holder, til: $untilLabel',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
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
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: startTime ?? const TimeOfDay(hour: 8, minute: 0),
                              builder: (context, child) {
                                return MediaQuery(
                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                  child: child!,
                                );
                              },
                            );
                            if (t != null) setDlg(() => startTime = t);
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(startTime == null ? 'Starttid' : _formatTime24(startTime!)),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: endTime ?? const TimeOfDay(hour: 16, minute: 0),
                              builder: (context, child) {
                                return MediaQuery(
                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                  child: child!,
                                );
                              },
                            );
                            if (t != null) setDlg(() => endTime = t);
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(endTime == null ? 'Sluttid' : _formatTime24(endTime!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: borrowerId != null &&
                            vehicleId != null &&
                            start != null &&
                            end != null &&
                            startTime != null &&
                            endTime != null
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

    if (ok != true ||
        borrowerId == null ||
        vehicleId == null ||
        start == null ||
        end == null ||
        startTime == null ||
        endTime == null) {
      return;
    }
    final selectedBorrowerId = borrowerId!;
    final selectedStart = start!;
    final selectedEnd = end!;
    final selectedStartTime = startTime!;
    final selectedEndTime = endTime!;

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
    final startAt = DateTime(
      selectedStart.year,
      selectedStart.month,
      selectedStart.day,
      selectedStartTime.hour,
      selectedStartTime.minute,
    );
    final endAt = DateTime(
      selectedEnd.year,
      selectedEnd.month,
      selectedEnd.day,
      selectedEndTime.hour,
      selectedEndTime.minute,
    );
    if (!endAt.isAfter(startAt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sluttdato/tid må være etter startdato/tid.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      await VehicleRentalService.createRental(
        companyId: cid,
        borrowerPartnerId: selectedBorrowerId,
        vehicle: vehicle,
        rentalStartAt: startAt,
        rentalEndAt: endAt,
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

  _ReturnSettlementSummary _computeReturnSettlement(VehicleRental rental) {
    final start = rental.rentalStartAt ??
        rental.rentalStart ??
        rental.approvedAt ??
        rental.ownerSubmittedAt ??
        rental.createdAt;
    final end = rental.returnSubmittedAt ?? DateTime.now();

    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final rentalDays = endDay.difference(startDay).inDays + 1;
    final chargeDays = rentalDays < 1 ? 1 : rentalDays;
    const dayRate = 1000;
    final daysAmount = chargeDays * dayRate;

    final expectedFuel = (rental.fuelLevel ?? '').trim().toLowerCase();
    final returnedFuel = (rental.returnFuelLevel ?? '').trim().toLowerCase();
    final fuelMismatch = expectedFuel.isNotEmpty &&
        returnedFuel.isNotEmpty &&
        expectedFuel != returnedFuel;
    final fuelFee = fuelMismatch ? 500 : 0;
    final total = daysAmount + fuelFee;

    final plannedEnd = rental.rentalEndAt ?? rental.rentalEnd;
    final returnedEarly = plannedEnd != null && end.isBefore(plannedEnd);

    return _ReturnSettlementSummary(
      chargeDays: chargeDays,
      dayRate: dayRate,
      daysAmount: daysAmount,
      fuelFee: fuelFee,
      fuelMismatch: fuelMismatch,
      totalAmount: total,
      returnedEarly: returnedEarly,
    );
  }

  Future<String?> _askReturnApprovalWithSettlement(VehicleRental rental) async {
    final summary = _computeReturnSettlement(rental);
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
            const Text(
              'Godkjenn retur og registrer trekk',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Registrer dette i trekkfilen:', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('MAVI nr: ${rental.unitCode ?? '—'}'),
                  Text('Reg.nr: ${rental.registrationNumber ?? '—'}'),
                  Text('Antall dager: ${summary.chargeDays}'),
                  Text('Sats per dag: ${summary.dayRate},-'),
                  Text('Sum leie: ${summary.daysAmount},-'),
                  Text(
                    summary.fuelMismatch
                        ? 'Drivstofftillegg: 500,- (nivå avviker)'
                        : 'Drivstofftillegg: 0,-',
                  ),
                  if (summary.returnedEarly)
                    const Text(
                      'Retur før avtalt sluttdato registrert.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Totalt trekk: ${summary.totalAmount},-',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Valgfri MAVI-kommentar',
                labelText: 'Kommentar',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final extra = ctrl.text.trim();
                final autoSummary =
                    'Trekkfil: MAVI ${rental.unitCode ?? '—'} / ${rental.registrationNumber ?? '—'} · '
                    '${summary.chargeDays} dager x ${summary.dayRate},- = ${summary.daysAmount},-'
                    '${summary.fuelMismatch ? ' + drivstoff 500,-' : ''} · '
                    'Totalt ${summary.totalAmount},-.';
                final finalComment = extra.isEmpty ? autoSummary : '$extra\n\n$autoSummary';
                Navigator.pop(ctx, finalComment);
              },
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.success),
              child: const Text('Godkjenn retur'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _approveReturn(VehicleRental rental) async {
    final comment = await _askReturnApprovalWithSettlement(rental);
    if (!mounted) return;
    if (comment == null) return;

    await VehicleRentalService.approveReturn(rental.id, maviComment: comment);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retur godkjent — registrer trekkfil med oppgitt beløp')),
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

  Future<void> _forceDeleteRental(VehicleRental rental) async {
    final reasonCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Superadmin: slett utleieavtale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dette sletter avtalen permanent og frigjør blokkering på bilen ${rental.registrationNumber ?? '—'}.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Årsak (valgfritt)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Skriv SLETT for å bekrefte',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () {
              if (confirmCtrl.text.trim().toUpperCase() != 'SLETT') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Skriv SLETT for å bekrefte permanent sletting.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett avtale'),
          ),
        ],
      ),
    );
    final reasonText = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    confirmCtrl.dispose();
    if (ok != true || !mounted) return;

    try {
      await VehicleRentalService.superadminForceDeleteRental(
        rentalId: rental.id,
        reason: reasonText.isEmpty ? null : reasonText,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utleieavtale slettet. Bil er frigjort fra blokkering.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette avtale: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showDetail(VehicleRental rental) async {
    await showVehicleRentalDetailSheet(
      context,
      rental: rental,
      actions: widget.canApproveRentals
          ? Column(
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
                if (widget.canForceDeleteRentals &&
                    VehicleRentalService.activeStatuses.contains(rental.status)) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _forceDeleteRental(rental);
                    },
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    label: const Text('Superadmin: Slett avtale og frigjør bil'),
                  ),
                ],
              ],
            )
          : null,
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
    final content = Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PartnerModernKpiGrid(
              items: [
                ('Til godkjenning', '${_count('pending_mavi')}'),
                ('Utleid', '${_count('approved')}'),
                ('Retur venter', '${_count('pending_return_mavi')}'),
                ('Arkiv', '${_count('returned')}'),
              ],
            ),
            PartnerSmartActionsPanel(
              title: 'Anbefalte handlinger',
              actions: [
                const PartnerSmartAction(
                  label: 'Opprett ny utleie',
                  hint: 'Start med låntaker, bil og periode',
                  icon: Icons.add_circle_outline,
                ),
                if (_count('pending_mavi') > 0)
                  const PartnerSmartAction(
                    label: 'Godkjenn ventende utlån',
                    hint: 'Sjekk bilder og detaljer før godkjenning',
                    icon: Icons.task_alt_outlined,
                  ),
              ],
            ),
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

    if (widget.nestedScroll) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverFillRemaining(hasScrollBody: false, child: content),
        ],
      );
    }

    return content;
  }

  Widget? _buildCardAction(VehicleRental r) {
    if (r.isApproved) {
      return FilledButton.icon(
        onPressed: () => _showDetail(r),
        style: FilledButton.styleFrom(
          backgroundColor: DriftProTheme.error,
          minimumSize: const Size(double.infinity, 44),
        ),
        icon: const Icon(Icons.assignment_return, size: 18),
        label: const Text('Se utlån / returstatus'),
      );
    }
    if (!widget.canApproveRentals) return null;
    if (r.isPendingMavi) {
      return FilledButton.icon(
        onPressed: () => _showDetail(r),
        style: FilledButton.styleFrom(
          backgroundColor: DriftProTheme.primaryGreen,
          minimumSize: const Size(double.infinity, 44),
        ),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('Se bilder før godkjenning'),
      );
    }
    if (r.isPendingReturnMavi) {
      return FilledButton.icon(
        onPressed: () => _showDetail(r),
        style: FilledButton.styleFrom(
          backgroundColor: DriftProTheme.success,
          minimumSize: const Size(double.infinity, 44),
        ),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('Se retur før godkjenning'),
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

class _ReturnSettlementSummary {
  final int chargeDays;
  final int dayRate;
  final int daysAmount;
  final int fuelFee;
  final bool fuelMismatch;
  final int totalAmount;
  final bool returnedEarly;

  const _ReturnSettlementSummary({
    required this.chargeDays,
    required this.dayRate,
    required this.daysAmount,
    required this.fuelFee,
    required this.fuelMismatch,
    required this.totalAmount,
    required this.returnedEarly,
  });
}
