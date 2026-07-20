import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/layout/mobile_shell_scaffold.dart';
import '../../../core/services/partner/vehicle_rental_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/vehicle_rental.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'vehicle_rental_ui.dart';

/// Dokumenter bil før utleie: avtale, 6 bilder, drivstoff og km.
/// Brukes av partner-portal og MAVI-ansatte.
class VehicleRentalCheckoutFlowScreen extends StatefulWidget {
  final VehicleRental rental;
  final Future<void> Function() onDone;

  const VehicleRentalCheckoutFlowScreen({
    super.key,
    required this.rental,
    required this.onDone,
  });

  @override
  State<VehicleRentalCheckoutFlowScreen> createState() =>
      _VehicleRentalCheckoutFlowScreenState();
}

class _VehicleRentalCheckoutFlowScreenState
    extends State<VehicleRentalCheckoutFlowScreen> {
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
    if ((rental.fuelLevel ?? '').trim().isNotEmpty) {
      _fuel.text = rental.fuelLevel!.trim();
    }
    if (rental.odometerKm != null) {
      _km.text = '${rental.odometerKm}';
    }
    if ((rental.ownerComment ?? '').trim().isNotEmpty) {
      _comment.text = rental.ownerComment!.trim();
    }
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
    if (!_photosComplete) {
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
          const SnackBar(content: Text('Dokumentasjon sendt — klar for godkjenning')),
        );
        await widget.onDone();
        if (mounted) Navigator.pop(context);
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
    return MobileAppScaffold(
      title: 'Dokumenter utleie',
      leading: const BackButton(),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          VehicleRentalMobileCard(rental: rental, showBlockedBanner: false),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leieavtale', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  vehicleRentalAgreementText(rental),
                  style: const TextStyle(fontSize: 12, height: 1.45),
                ),
              ],
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
          const SizedBox(height: 4),
          Text(
            'Front, bak, høyre, venstre, last/skap og dashboard — kan tas av MAVI-ansatt eller partner.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
          ),
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
                ? const SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                : const Icon(Icons.send),
            label: const Text('Send til godkjenning'),
          ),
        ],
      ),
    );
  }
}
