import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../last_mile/services/lm_warehouse_service.dart';

class DriverScanScreen extends StatefulWidget {
  const DriverScanScreen({super.key});

  @override
  State<DriverScanScreen> createState() => _DriverScanScreenState();
}

class _DriverScanScreenState extends State<DriverScanScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  String? _lastScan;

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code == _lastScan) return;
    _lastScan = code;
    final row = await LmWarehouseService.scanReceive(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(row != null ? 'Mottatt: $code' : 'Feil ved $code')),
    );
    setState(() {});
  }

  Future<void> _searchItems() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    final list = await LmWarehouseService.search(q);
    setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: MobileScanner(onDetect: _onDetect),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Søk strekkode / vare',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(onPressed: _searchItems, icon: const Icon(Icons.search)),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Text('Skann eller søk', style: DriftProTheme.bodyMd))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final it = _items[i];
                    return ListTile(
                      title: Text(it['barcode']?.toString() ?? ''),
                      subtitle: Text('${it['state']} · hylle ${it['shelf_location'] ?? '-'}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
