import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/hms/equipment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import '../../../core/hms/truck_inspection_templates.dart';
import 'equipment_service_book_screen.dart';
import 'equipment_truck_profile_screen.dart';

class EquipmentFormScreen extends StatefulWidget {
  final UserProfile profile;
  final Equipment? existing;
  final Map<String, String> profileNames;

  const EquipmentFormScreen({
    super.key,
    required this.profile,
    this.existing,
    this.profileNames = const {},
  });

  @override
  State<EquipmentFormScreen> createState() => _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends State<EquipmentFormScreen> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _plate = TextEditingController();
  final _supplier = TextEditingController();
  final _notes = TextEditingController();
  final _price = TextEditingController();

  EquipmentCategory _category = EquipmentCategory.other;
  TruckSubtype _truckSubtype = TruckSubtype.fork;
  EquipmentStatus _status = EquipmentStatus.ok;
  String? _responsibleId;
  String? _assignedId;
  DateTime? _purchaseDate;
  DateTime? _nextService;
  DateTime? _nextWater;
  DateTime? _warrantyUntil;
  List<String> _receiptUrls = [];
  List<String> _manualUrls = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _brand.text = e.brand ?? '';
      _model.text = e.model ?? '';
      _serial.text = e.serialNumber ?? '';
      _plate.text = e.licensePlate ?? '';
      _supplier.text = e.supplier ?? '';
      _notes.text = e.notes ?? '';
      if (e.purchasePrice != null) _price.text = e.purchasePrice.toString();
      _category = e.category;
      _truckSubtype = TruckSubtypeExtension.fromDb(e.truckSubtype);
      _status = e.status;
      _responsibleId = e.responsibleUserId;
      _assignedId = e.assignedTo;
      _purchaseDate = e.purchaseDate;
      _nextService = e.nextService;
      _nextWater = e.nextWaterCheck;
      _warrantyUntil = e.warrantyUntil;
      _receiptUrls = List.from(e.receiptUrls);
      _manualUrls = List.from(e.serviceManualUrls);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _serial.dispose();
    _plate.dispose();
    _supplier.dispose();
    _notes.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickFiles(bool isManual) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || widget.profile.companyId == null) return;
    setState(() => _saving = true);
    try {
      for (final f in result.files) {
        if (f.bytes == null) continue;
        final url = await EquipmentService.uploadDocument(
          companyId: widget.profile.companyId!,
          fileName: f.name,
          bytes: f.bytes!,
          subfolder: isManual ? 'manuals' : 'receipts',
        );
        setState(() {
          if (isManual) {
            _manualUrls.add(url);
          } else {
            _receiptUrls.add(url);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final companyId = widget.profile.companyId;
    if (companyId == null) return;

    setState(() => _saving = true);
    try {
      final item = Equipment(
        id: widget.existing?.id ?? const Uuid().v4(),
        companyId: companyId,
        name: _name.text.trim(),
        category: _category,
        brand: _brand.text.isEmpty ? null : _brand.text,
        model: _model.text.isEmpty ? null : _model.text,
        serialNumber: _serial.text.isEmpty ? null : _serial.text,
        licensePlate: _plate.text.isEmpty ? null : _plate.text,
        status: _status,
        supplier: _supplier.text.isEmpty ? null : _supplier.text,
        purchaseDate: _purchaseDate,
        purchasePrice: double.tryParse(_price.text.replaceAll(',', '.')),
        warrantyUntil: _warrantyUntil,
        nextService: _nextService,
        nextWaterCheck: _nextWater,
        responsibleUserId: _responsibleId,
        assignedTo: _assignedId,
        registeredBy: widget.profile.id,
        departmentId: widget.profile.departmentId,
        receiptUrls: _receiptUrls,
        serviceManualUrls: _manualUrls,
        notes: _notes.text.isEmpty ? null : _notes.text,
        truckSubtype: _category == EquipmentCategory.truck ||
                _category == EquipmentCategory.vehicle
            ? _truckSubtype.dbValue
            : null,
        controlEnabled: true,
      );

      final saved = await EquipmentService.save(
        item,
        id: _isEdit ? widget.existing!.id : null,
      );

      if (!_isEdit && _receiptUrls.isNotEmpty) {
        await EquipmentService.addPurchase(
          EquipmentPurchase(
            id: const Uuid().v4(),
            companyId: companyId,
            equipmentId: saved.id,
            itemName: item.name,
            serialNumber: item.serialNumber,
            purchasedAt: _purchaseDate ?? DateTime.now(),
            purchasedByUserId: widget.profile.id,
            assignedToUserId: _assignedId,
            departmentId: widget.profile.departmentId,
            supplier: item.supplier,
            amount: item.purchasePrice,
            receiptUrls: _receiptUrls,
          ),
        );
      }

      if (!mounted) return;
      if (!_isEdit &&
          (_category == EquipmentCategory.truck ||
              _category == EquipmentCategory.vehicle)) {
        await EquipmentService.ensureServiceBook(saved.id);
        if (!mounted) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EquipmentTruckProfileScreen(
              equipmentId: saved.id,
              profile: widget.profile,
              profileNames: widget.profileNames,
            ),
          ),
        );
        return;
      }
      if (!_isEdit && _category == EquipmentCategory.machine) {
        await EquipmentService.ensureServiceBook(saved.id);
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profiles = widget.profileNames.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Rediger utstyr' : 'Registrer utstyr'),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
          child: _saving
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(_isEdit ? 'LAGRE' : 'REGISTRER'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Type utstyr', style: DriftProTheme.labelMd),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: EquipmentCategory.values.map((c) {
              final sel = _category == c;
              return ChoiceChip(
                label: Text(c.label),
                selected: sel,
                onSelected: (_) => setState(() => _category = c),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _field('Navn *', _name, hint: 'F.eks. Lenovo laptop / Toyota 8FBE'),
          _field('Merke', _brand),
          _field('Modell', _model),
          _field('Serienummer (SN)', _serial),
          if (_category == EquipmentCategory.truck ||
              _category == EquipmentCategory.vehicle) ...[
            Text('Truck-type', style: DriftProTheme.labelMd),
            const SizedBox(height: 8),
            SegmentedButton<TruckSubtype>(
              segments: [
                ButtonSegment(value: TruckSubtype.fork, label: Text(TruckSubtype.fork.label)),
                ButtonSegment(value: TruckSubtype.clamp, label: Text(TruckSubtype.clamp.label)),
              ],
              selected: {_truckSubtype},
              onSelectionChanged: (v) => setState(() => _truckSubtype = v.first),
            ),
            const SizedBox(height: 12),
            _field('Skiltnummer', _plate),
          ],
          _field('Leverandør', _supplier),
          _field('Innkjøpspris', _price, keyboard: TextInputType.number),
          const SizedBox(height: 12),
          _dateTile('Innkjøpsdato', _purchaseDate, (d) => _purchaseDate = d),
          _dateTile('Garanti til', _warrantyUntil, (d) => _warrantyUntil = d),
          if (_category == EquipmentCategory.truck ||
              _category == EquipmentCategory.vehicle) ...[
            _dateTile('Neste vann/batteri', _nextWater, (d) => _nextWater = d),
            _dateTile('Neste service', _nextService, (d) => _nextService = d),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _responsibleId,
            decoration: const InputDecoration(labelText: 'Ansvarlig for vedlikehold'),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              ...profiles.map(
                (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
              ),
            ],
            onChanged: (v) => setState(() => _responsibleId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _assignedId,
            decoration: const InputDecoration(labelText: 'Tildelt ansatt'),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              ...profiles.map(
                (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
              ),
            ],
            onChanged: (v) => setState(() => _assignedId = v),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _pickFiles(false),
            icon: const Icon(Icons.receipt_long),
            label: Text('Kvittering (${_receiptUrls.length})'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _pickFiles(true),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text('Servicehefte PDF (${_manualUrls.length})'),
          ),
          const SizedBox(height: 16),
          _field('Notater', _notes, maxLines: 3),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? hint, int maxLines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime?> set) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        value != null
            ? '${value.day}.${value.month}.${value.year}'
            : 'Ikke satt',
      ),
      trailing: const Icon(Icons.calendar_today),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2010),
          lastDate: DateTime(2035),
        );
        if (d != null) setState(() => set(d));
      },
    );
  }
}
