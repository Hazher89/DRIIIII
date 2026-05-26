import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:signature/signature.dart';

import '../../last_mile/models/lm_route.dart';
import '../../last_mile/services/lm_pod_service.dart';

class DriverPodScreen extends StatefulWidget {
  final LmRouteStop stop;

  const DriverPodScreen({super.key, required this.stop});

  @override
  State<DriverPodScreen> createState() => _DriverPodScreenState();
}

class _DriverPodScreenState extends State<DriverPodScreen> {
  final _signer = TextEditingController();
  final _signature = SignatureController(penStrokeWidth: 2, penColor: Colors.black);
  bool _saving = false;

  Future<void> _save() async {
    if (_signer.text.trim().isEmpty) return;
    setState(() => _saving = true);

    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    await LmPodService.recordDelivery(
      routeStopId: widget.stop.id,
      signerName: _signer.text.trim(),
      lat: lat,
      lng: lng,
      notes: _signature.isNotEmpty ? 'Signatur registrert' : null,
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.stop.order;
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(o?.customerName ?? 'Kunde', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(o?.addressLine ?? ''),
          const SizedBox(height: 16),
          TextField(
            controller: _signer,
            decoration: const InputDecoration(labelText: 'Mottakers navn', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Signatur'),
          Container(
            height: 160,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
            child: Signature(controller: _signature, backgroundColor: Colors.white),
          ),
          TextButton(onPressed: () => _signature.clear(), child: const Text('Tøm signatur')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Bekreft levering'),
          ),
        ],
      ),
    );
  }
}
