import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/services/native_permissions_service.dart';
import '../../../core/services/partner/partner_driver_deviation_refs.dart';
import '../../../core/services/partner/partner_driver_deviation_service.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_driver_deviation.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_driver_deviation_detail_sheet.dart';

/// Sjåførportal: meld avvik (kamera/galleri) + arkiv over egne innsendinger.
/// Samme kode for Android, iOS og web.
class DriverPortalAvvikPage extends StatefulWidget {
  const DriverPortalAvvikPage({
    super.key,
    required this.partner,
    required this.profile,
  });

  final Partner partner;
  final UserProfile profile;

  @override
  State<DriverPortalAvvikPage> createState() => _DriverPortalAvvikPageState();
}

class _DriverPortalAvvikPageState extends State<DriverPortalAvvikPage>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  final _commentCtrl = TextEditingController();
  final _orderRefCtrl = TextEditingController();
  final List<PartnerDriverDeviationMedia> _images = [];
  PartnerDriverDeviationMedia? _video;
  late DateTime _day;
  late TabController _tabs;
  List<RoutePdfCustomer> _customers = const [];
  RoutePdfCustomer? _customer;
  List<PartnerDriverDeviation> _mine = const [];
  bool _loadingCustomers = true;
  bool _loadingMine = true;
  bool _submitting = false;
  String? _customerError;
  String? _mineError;

  @override
  void initState() {
    super.initState();
    _day = _dateOnly(DateTime.now());
    _tabs = TabController(length: 2, vsync: this);
    _loadCustomers();
    _loadMine();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _orderRefCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final vehicleId = widget.profile.partnerVehicleId;
    if (vehicleId == null) {
      setState(() {
        _loadingCustomers = false;
        _customerError = 'Kontoen er ikke knyttet til en MAVI-bil.';
      });
      return;
    }
    setState(() {
      _loadingCustomers = true;
      _customerError = null;
      _customer = null;
      _customers = const [];
    });
    try {
      final customers = await PartnerService.fetchRouteCustomersForVehicleDay(
        companyId: widget.partner.companyId,
        partnerVehicleId: vehicleId,
        day: _day,
      );
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _loadingCustomers = false;
        if (customers.isEmpty) {
          _customerError =
              'Ingen kunder funnet på ruten ${DateFormat('d. MMMM', 'nb').format(_day)}.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCustomers = false;
        _customerError = 'Kunne ikke hente kunder: $e';
      });
    }
  }

  Future<void> _loadMine() async {
    setState(() {
      _loadingMine = true;
      _mineError = null;
    });
    try {
      final items = await PartnerDriverDeviationService.listMine(
        companyId: widget.partner.companyId,
        limit: 80,
      );
      if (!mounted) return;
      setState(() {
        _mine = items;
        _loadingMine = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMine = false;
        _mineError = 'Kunne ikke hente arkiv: $e';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('nb'),
    );
    if (picked == null) return;
    setState(() => _day = _dateOnly(picked));
    await _loadCustomers();
  }

  Future<void> _setDay(DateTime day) async {
    setState(() => _day = _dateOnly(day));
    await _loadCustomers();
  }

  Future<void> _addImageBytes(XFile file) async {
    final media = PartnerDriverDeviationMedia(
      name: file.name,
      bytes: await file.readAsBytes(),
    );
    if (mounted) setState(() => _images.add(media));
  }

  Future<void> _takePhoto() async {
    if (!await NativePermissionsService.ensureCamera(context: context)) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return;
    await _addImageBytes(file);
  }

  Future<void> _pickImages() async {
    if (!await NativePermissionsService.ensurePhotos(context: context)) return;
    final files = await _picker.pickMultiImage(imageQuality: 85);
    for (final file in files) {
      await _addImageBytes(file);
    }
  }

  Future<void> _setVideo(XFile file) async {
    final media = PartnerDriverDeviationMedia(
      name: file.name,
      bytes: await file.readAsBytes(),
    );
    if (mounted) setState(() => _video = media);
  }

  Future<void> _recordVideo() async {
    if (!await NativePermissionsService.ensureCamera(context: context)) return;
    final file = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5),
    );
    if (file == null) return;
    await _setVideo(file);
  }

  Future<void> _pickVideo() async {
    if (!await NativePermissionsService.ensurePhotos(context: context)) return;
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (file == null) return;
    await _setVideo(file);
  }

  Future<void> _submit() async {
    final customer = _customer;
    final vehicleId = widget.profile.partnerVehicleId;
    final comment = _commentCtrl.text.trim();
    if (customer == null) {
      _message('Velg en kunde fra ruten.');
      return;
    }
    if (vehicleId == null) {
      _message('Kontoen mangler kjøretøytilknytning.');
      return;
    }
    if (comment.isEmpty) {
      _message('Skriv hva avviket gjelder.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final rawFreight = customer.freightUnit?.trim() ?? '';
      final freightStored =
          PartnerDriverDeviationRefs.freightUnitForStorage(rawFreight);
      final customerRef =
          PartnerDriverDeviationRefs.primaryFreightUnit(rawFreight) ??
              (freightStored.isNotEmpty
                  ? freightStored.split(',').first.trim()
                  : customer.sequence.toString());
      final bilag = PartnerDriverDeviationRefs.primaryBilag(
        salesOrder: customer.salesOrder,
        manual: _orderRefCtrl.text,
        freightRaw: rawFreight,
      );
      if (bilag == null || bilag.isEmpty) {
        _message(
          'Fant ikke bilagsnummer (starter med 2) for denne kunden. '
          'Skriv inn bilag manuelt.',
          error: true,
        );
        setState(() => _submitting = false);
        return;
      }
      await PartnerDriverDeviationService.create(
        companyId: widget.partner.companyId,
        partnerId: widget.partner.id,
        partnerVehicleId: vehicleId,
        routeDate: _day,
        customerName: customer.name,
        freightUnit: freightStored.isNotEmpty ? freightStored : customerRef,
        customerRef: customerRef,
        orderRef: bilag,
        comment: comment,
        images: _images,
        videos: _video == null ? const [] : [_video!],
      );
      if (!mounted) return;
      _commentCtrl.clear();
      _orderRefCtrl.clear();
      setState(() {
        _images.clear();
        _video = null;
        _customer = null;
      });
      _message('Avviket er sendt. MAVI og CCC kan se det med én gang.');
      await _loadMine();
      if (mounted) _tabs.animateTo(1);
    } catch (e) {
      if (mounted) _message('Kunne ikke sende avvik: $e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? Colors.red : null),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _customerLabel(RoutePdfCustomer customer) {
    return PartnerDriverDeviationRefs.customerPickerLabel(
      name: customer.name,
      freightRaw: customer.freightUnit,
      salesOrder: customer.salesOrder,
      sequence: customer.sequence,
    );
  }

  void _onCustomerChanged(RoutePdfCustomer? value) {
    setState(() {
      _customer = value;
      if (value == null) return;
      final bilag = PartnerDriverDeviationRefs.primaryBilag(
        salesOrder: value.salesOrder,
        freightRaw: value.freightUnit,
      );
      if (bilag != null) {
        _orderRefCtrl.text = bilag;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avvik'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Nytt'),
            Tab(
              text: _mine.isEmpty ? 'Mine' : 'Mine (${_mine.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildComposeTab(),
          _buildArchiveTab(),
        ],
      ),
    );
  }

  Widget _buildComposeTab() {
    final now = _dateOnly(DateTime.now());
    final yesterday = now.subtract(const Duration(days: 1));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Meld avvik på ruten',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Velg kunde → skriv → ta bilde/video → Send. '
          'Går direkte til Dropbox, MAVI-portalen og CCC-søk i chat.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('I dag'),
              selected: _sameDay(_day, now),
              onSelected: (_) => _setDay(now),
            ),
            ChoiceChip(
              label: const Text('I går'),
              selected: _sameDay(_day, yesterday),
              onSelected: (_) => _setDay(yesterday),
            ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(
                _sameDay(_day, now) || _sameDay(_day, yesterday)
                    ? 'Velg dato'
                    : DateFormat('d. MMM yyyy', 'nb').format(_day),
              ),
              onPressed: _pickDate,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loadingCustomers)
          const Padding(
            padding: EdgeInsets.all(20),
            child: DriftProLoadingCenter(),
          )
        else ...[
          DropdownButtonFormField<RoutePdfCustomer>(
            initialValue: _customer,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Kunde på ruten *',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
            ),
            items: _customers
                .map(
                  (customer) => DropdownMenuItem(
                    value: customer,
                    child: Text(
                      _customerLabel(customer),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _customers.isEmpty ? null : _onCustomerChanged,
          ),
          if (_customerError != null) ...[
            const SizedBox(height: 8),
            Text(
              _customerError!,
              style: const TextStyle(color: Colors.orange),
            ),
          ],
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _orderRefCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Bilagsnummer *',
            hintText: 'Starter med 2…',
            helperText: 'Fylles automatisk fra PDF (Sales order).',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentCtrl,
          minLines: 6,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Beskriv avviket *',
            hintText: 'Skriv så mye du trenger…',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Bilder og video',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!kIsWeb)
              FilledButton.tonalIcon(
                onPressed: _submitting ? null : _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Ta bilde'),
              ),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _images.isEmpty
                    ? 'Fra galleri'
                    : 'Bilder (${_images.length})',
              ),
            ),
            if (!kIsWeb)
              FilledButton.tonalIcon(
                onPressed: _submitting ? null : _recordVideo,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Ta video'),
              ),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: Text(_video == null ? 'Video fra galleri' : 'Video valgt'),
            ),
          ],
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _images[index].bytes,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: InkWell(
                      onTap: () => setState(() => _images.removeAt(index)),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_video != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.videocam,
              color: DriftProTheme.primaryGreen,
            ),
            title: Text(_video!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${(_video!.bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB',
            ),
            trailing: IconButton(
              tooltip: 'Fjern video',
              onPressed: () => setState(() => _video = null),
              icon: const Icon(Icons.close),
            ),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _submitting ? 'Sender…' : 'Send avvik',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArchiveTab() {
    if (_loadingMine) {
      return const DriftProLoadingCenter();
    }
    if (_mineError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_mineError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadMine,
                child: const Text('Prøv igjen'),
              ),
            ],
          ),
        ),
      );
    }
    if (_mine.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadMine,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Ingen avvik sendt ennå',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Når du sender et avvik, dukker det opp her.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _mine.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final item = _mine[index];
          final bilag = item.orderRef?.trim() ?? '';
          final media =
              item.imageUrls.length + item.videoUrls.length;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showPartnerDriverDeviationDetail(context, item),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.customerName?.trim().isNotEmpty == true
                                ? item.customerName!
                                : 'Ukjent kunde',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat('d.M.yyyy HH:mm', 'nb')
                              .format(item.createdAt.toLocal()),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (bilag.isNotEmpty) 'Bilag $bilag',
                        DateFormat('d. MMM', 'nb').format(item.routeDate),
                        if (media > 0) '$media fil(er)',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.comment,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
