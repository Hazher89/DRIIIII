import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/services/partner/vehicle_rental_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/vehicle_rental.dart';
import '../widgets/vehicle_rental_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Bil-eier og låntaker: utleie, retur, arkiv.
class OwnerPortalVehicleRentalPage extends StatefulWidget {
  final Partner partner;

  const OwnerPortalVehicleRentalPage({super.key, required this.partner});

  @override
  State<OwnerPortalVehicleRentalPage> createState() => _OwnerPortalVehicleRentalPageState();
}

class _OwnerPortalVehicleRentalPageState extends State<OwnerPortalVehicleRentalPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  List<VehicleRental> _asLender = [];
  List<VehicleRental> _asBorrower = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lender = await VehicleRentalService.fetchForLenderPartner(widget.partner.id);
    final borrower = await VehicleRentalService.fetchForBorrowerPartner(widget.partner.id);
    if (mounted) {
      setState(() {
        _asLender = lender;
        _asBorrower = borrower;
        _loading = false;
      });
    }
  }

  Future<void> _openLenderFlow(VehicleRental rental) async {
    if (rental.isPendingOwner) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _OwnerCheckoutFlowScreen(rental: rental, onDone: _load),
        ),
      );
      return;
    }
    if (rental.isApproved) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _BorrowerReturnFlowScreen(rental: rental, onDone: _load),
        ),
      );
      return;
    }
    await showVehicleRentalDetailSheet(context, rental: rental);
  }

  Future<void> _openBorrowerFlow(VehicleRental rental) async {
    if (rental.isPendingOwner) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _OwnerCheckoutFlowScreen(rental: rental, onDone: _load),
        ),
      );
      return;
    }
    if (rental.isApproved) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _BorrowerReturnFlowScreen(rental: rental, onDone: _load),
        ),
      );
      return;
    }
    await showVehicleRentalDetailSheet(context, rental: rental);
  }

  @override
  Widget build(BuildContext context) {
    final mineRentalsById = <String, VehicleRental>{
      for (final r in _asLender) r.id: r,
      for (final r in _asBorrower)
        if (r.isPendingOwner || r.isPendingMavi) r.id: r,
    };
    final mineRentals = mineRentalsById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final borrowerVisible = _asBorrower.where((r) => !r.isPendingOwner && !r.isPendingMavi).toList();

    final lenderPending = mineRentals.where((r) => r.isPendingOwner).length;
    final borrowerActive = _asBorrower.where((r) => r.isApproved).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utleie av bil'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: lenderPending > 0 ? 'Mine biler ($lenderPending)' : 'Mine biler'),
            Tab(text: borrowerActive > 0 ? 'Lånte biler ($borrowerActive)' : 'Lånte biler'),
          ],
        ),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : TabBarView(
              controller: _tabs,
              children: [
                _LenderTab(rentals: mineRentals, onOpen: _openLenderFlow, onRefresh: _load),
                _BorrowerTab(rentals: borrowerVisible, onOpen: _openBorrowerFlow, onRefresh: _load),
              ],
            ),
    );
  }
}

class _LenderTab extends StatelessWidget {
  final List<VehicleRental> rentals;
  final Future<void> Function(VehicleRental) onOpen;
  final Future<void> Function() onRefresh;

  const _LenderTab({required this.rentals, required this.onOpen, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final pending = rentals.where((r) => r.isPendingOwner || r.isPendingMavi).toList();
    final activeOnLoan = rentals.where((r) => r.isApproved).toList();
    final pendingReturn = rentals.where((r) => r.isPendingReturnMavi).toList();
    final rest = rentals.where((r) => !r.isPendingOwner && !r.isApproved && !r.isPendingReturnMavi).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (pending.isNotEmpty) ...[
            _SectionHeader(title: 'Til behandling', count: pending.length, color: DriftProTheme.warning),
            ...pending.map(
              (r) => VehicleRentalMobileCard(
                rental: r,
                onTap: () => onOpen(r),
                action: FilledButton.icon(
                  onPressed: () => onOpen(r),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(r.isPendingOwner ? 'Dokumenter og send' : 'Venter MAVI-godkjenning'),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (activeOnLoan.isNotEmpty) ...[
            _SectionHeader(title: 'Aktive utlån', count: activeOnLoan.length, color: DriftProTheme.error),
            ...activeOnLoan.map(
              (r) => VehicleRentalMobileCard(
                rental: r,
                onTap: () => onOpen(r),
                showBlockedBanner: true,
                action: FilledButton.icon(
                  onPressed: () => onOpen(r),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.error,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  icon: const Icon(Icons.assignment_return, size: 18),
                  label: const Text('Returner før sluttdato'),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (pendingReturn.isNotEmpty) ...[
            _SectionHeader(
              title: 'Venter retur-godkjenning',
              count: pendingReturn.length,
              color: Colors.deepOrange,
            ),
            ...pendingReturn.map(
              (r) => VehicleRentalMobileCard(
                rental: r,
                onTap: () => onOpen(r),
                showBlockedBanner: true,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionHeader(title: 'Arkiv', count: rest.length, color: DriftProTheme.accentBlue),
          if (rest.isEmpty && pending.isEmpty && activeOnLoan.isEmpty && pendingReturn.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Ingen utleier registrert på bedriften din.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else
            ...rest.map(
              (r) => VehicleRentalMobileCard(
                rental: r,
                onTap: () => onOpen(r),
              ),
            ),
        ],
      ),
    );
  }
}

class _BorrowerTab extends StatelessWidget {
  final List<VehicleRental> rentals;
  final Future<void> Function(VehicleRental) onOpen;
  final Future<void> Function() onRefresh;

  const _BorrowerTab({required this.rentals, required this.onOpen, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final active = rentals.where((r) => r.isApproved).toList();
    final pendingReturn = rentals.where((r) => r.isPendingReturnMavi).toList();
    final archive = rentals.where((r) => r.isReturned || r.isRejected || r.isCancelled).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (active.isNotEmpty) ...[
            _SectionHeader(title: 'Aktive lån (blokkert)', count: active.length, color: DriftProTheme.error),
            ...active.map(
              (r) => VehicleRentalMobileCard(
                rental: r,
                onTap: () => onOpen(r),
                showBlockedBanner: true,
                action: FilledButton.icon(
                  onPressed: () => onOpen(r),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.error,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  icon: const Icon(Icons.assignment_return, size: 20),
                  label: const Text('Returner bil'),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (pendingReturn.isNotEmpty) ...[
            _SectionHeader(title: 'Retur sendt', count: pendingReturn.length, color: Colors.deepOrange),
            ...pendingReturn.map(
              (r) => VehicleRentalMobileCard(rental: r, onTap: () => onOpen(r)),
            ),
            const SizedBox(height: 16),
          ],
          _SectionHeader(title: 'Arkiv', count: archive.length, color: DriftProTheme.success),
          if (active.isEmpty && pendingReturn.isEmpty && archive.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Ingen lånte biler.\nNår MAVI godkjenner utleie til dere, vises bilen her.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else
            ...archive.map(
              (r) => VehicleRentalMobileCard(
                rental: r,
                onTap: () => onOpen(r),
                showBlockedBanner: false,
                action: r.isApproved
                    ? FilledButton.icon(
                        onPressed: () => onOpen(r),
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.error,
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        icon: const Icon(Icons.assignment_return, size: 18),
                        label: const Text('Returner før sluttdato'),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: 8),
          Text('$title ($count)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }
}

class _OwnerCheckoutFlowScreen extends StatefulWidget {
  final VehicleRental rental;
  final Future<void> Function() onDone;

  const _OwnerCheckoutFlowScreen({required this.rental, required this.onDone});

  @override
  State<_OwnerCheckoutFlowScreen> createState() => _OwnerCheckoutFlowScreenState();
}

class _OwnerCheckoutFlowScreenState extends State<_OwnerCheckoutFlowScreen> {
  late Map<String, String> _photos;
  final _fuel = TextEditingController();
  final _km = TextEditingController();
  final _comment = TextEditingController();
  bool _agreementRead = false;
  bool _submitting = false;

  VehicleRental get rental => widget.rental;

  @override
  void initState() {
    super.initState();
    _photos = Map<String, String>.from(rental.photos);
  }

  @override
  void dispose() {
    _fuel.dispose();
    _km.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _capture(String slot, List<int> bytes) async {
    setState(() => _submitting = true);
    try {
      final path = await VehicleRentalService.uploadPhoto(
        companyId: rental.companyId,
        rentalId: rental.id,
        slotKey: slot,
        bytes: Uint8List.fromList(bytes),
      );
      setState(() => _photos[slot] = path);
      await VehicleRentalService.updatePhotos(rental.id, _photos);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    if (!_agreementRead) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bekreft at du har lest avtalen')),
      );
      return;
    }
    if (!rental.photosComplete && !_photosComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ta alle 6 bildene')),
      );
      return;
    }
    final km = int.tryParse(_km.text.trim());
    if (_fuel.text.trim().isEmpty || km == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn drivstoff og kilometerstand')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await VehicleRentalService.ownerSubmit(
        rentalId: rental.id,
        photos: _photos,
        fuelLevel: _fuel.text.trim(),
        odometerKm: km,
        ownerComment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sendt til MAVI for godkjenning')),
        );
        await widget.onDone();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _photosComplete =>
      VehicleRentalPhotoSlot.requiredKeys.every((k) => (_photos[k] ?? '').isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dokumenter utleie')),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          VehicleRentalMobileCard(rental: rental, showBlockedBanner: false),
          const SizedBox(height: 16),
          _InfoBlock(
            title: 'Leieavtale',
            child: Text(
              vehicleRentalAgreementText(rental),
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _agreementRead,
            onChanged: (v) => setState(() => _agreementRead = v == true),
            title: const Text('Jeg har lest og aksepterer avtalen', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 8),
          const Text('6 bilder (obligatorisk)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          VehicleRentalPhotoGrid(photos: _photos, onCapture: _capture),
          const SizedBox(height: 16),
          TextField(
            controller: _fuel,
            decoration: const InputDecoration(
              labelText: 'Drivstoff / lade-tilstand *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _km,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kilometerstand *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Kommentar (valgfritt)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 52),
            ),
            icon: _submitting
                ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                : const Icon(Icons.send),
            label: const Text('Send til godkjenning'),
          ),
        ],
      ),
    );
  }
}

class _BorrowerReturnFlowScreen extends StatefulWidget {
  final VehicleRental rental;
  final Future<void> Function() onDone;

  const _BorrowerReturnFlowScreen({required this.rental, required this.onDone});

  @override
  State<_BorrowerReturnFlowScreen> createState() => _BorrowerReturnFlowScreenState();
}

class _BorrowerReturnFlowScreenState extends State<_BorrowerReturnFlowScreen> {
  late Map<String, String> _photos;
  final _fuel = TextEditingController();
  final _km = TextEditingController();
  final _comment = TextEditingController();
  bool _submitting = false;

  VehicleRental get rental => widget.rental;

  @override
  void initState() {
    super.initState();
    _photos = Map<String, String>.from(rental.returnPhotos);
  }

  @override
  void dispose() {
    _fuel.dispose();
    _km.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _capture(String slot, List<int> bytes) async {
    setState(() => _submitting = true);
    try {
      final path = await VehicleRentalService.uploadPhoto(
        companyId: rental.companyId,
        rentalId: rental.id,
        slotKey: slot,
        bytes: Uint8List.fromList(bytes),
        isReturn: true,
      );
      setState(() => _photos[slot] = path);
      await VehicleRentalService.updatePhotos(rental.id, _photos, isReturn: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    if (!_photosComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ta alle 6 bildene ved retur')),
      );
      return;
    }
    final km = int.tryParse(_km.text.trim());
    if (_fuel.text.trim().isEmpty || km == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn drivstoff og kilometerstand')),
      );
      return;
    }

    final plannedEnd = rental.rentalEndAt ?? rental.rentalEnd;
    final now = DateTime.now();
    final isEarlyReturn = plannedEnd != null && now.isBefore(plannedEnd);
    final plannedEndLabel = plannedEnd == null
        ? null
        : '${plannedEnd.day}.${plannedEnd.month}.${plannedEnd.year} '
            '${plannedEnd.hour.toString().padLeft(2, '0')}:${plannedEnd.minute.toString().padLeft(2, '0')}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send retur?'),
        content: Text(
          'Du returnerer ${rental.registrationNumber ?? 'bilen'} til ${rental.lenderPartnerName ?? 'utleier'}.\n'
          '${isEarlyReturn ? 'Dette er retur før avtalt sluttdato (${plannedEndLabel ?? 'ukjent'}).\n' : ''}'
          'MAVI må godkjenne før bilen blir grønn og tilgjengelig igjen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send retur')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      await VehicleRentalService.borrowerSubmitReturn(
        rentalId: rental.id,
        returnPhotos: _photos,
        fuelLevel: _fuel.text.trim(),
        odometerKm: km,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retur sendt — venter MAVI-godkjenning')),
        );
        await widget.onDone();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _photosComplete =>
      VehicleRentalPhotoSlot.requiredKeys.every((k) => (_photos[k] ?? '').isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Returner bil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DriftProTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DriftProTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, color: DriftProTheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Reg.nr ${rental.registrationNumber ?? '—'} er blokkert til retur er godkjent av MAVI.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: DriftProTheme.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          VehicleRentalMobileCard(rental: rental, showBlockedBanner: false),
          const SizedBox(height: 16),
          const Text('6 bilder ved retur (obligatorisk)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          VehicleRentalPhotoGrid(photos: _photos, onCapture: _capture),
          const SizedBox(height: 16),
          TextField(
            controller: _fuel,
            decoration: const InputDecoration(
              labelText: 'Drivstoff / lade-tilstand *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _km,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kilometerstand *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Kommentar (valgfritt)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.error,
              minimumSize: const Size(double.infinity, 52),
            ),
            icon: _submitting
                ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                : const Icon(Icons.assignment_return),
            label: const Text('Send retur til godkjenning'),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoBlock({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
