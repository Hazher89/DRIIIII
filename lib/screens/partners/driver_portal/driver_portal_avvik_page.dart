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
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_driver_deviation_detail_sheet.dart';

/// Partner-portal avvik (sjåfør / bil-eier / ansatt med tillatelse).
///
/// - Sjåfør: meld på egen bil + arkiv «Mine» (egne)
/// - Bil-eier: velg bil, meld, «Mine» = alle avvik i firmaet (med hvem som sendte)
/// - Ansatt (med can_report_deviations): velg bil, meld, «Mine» = egne
///
/// MAVI arbeidsgiver ser alt under Partnere → Sjåføravvik (eget panel).
class DriverPortalAvvikPage extends StatefulWidget {
  const DriverPortalAvvikPage({
    super.key,
    required this.partner,
    required this.profile,
    this.isOwnerMode = false,
    this.isStaffMode = false,
  });

  final Partner partner;
  final UserProfile profile;

  /// Bil-eier / bedriftsansvarlig i partnerfirmaet.
  final bool isOwnerMode;

  /// Ansatt med tillatelse til å sende avvik.
  final bool isStaffMode;

  @override
  State<DriverPortalAvvikPage> createState() => _DriverPortalAvvikPageState();
}

class _DriverPortalAvvikPageState extends State<DriverPortalAvvikPage>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  final _commentCtrl = TextEditingController();
  final _orderRefCtrl = TextEditingController();
  final _customerSearchCtrl = TextEditingController();
  final List<PartnerDriverDeviationMedia> _images = [];
  PartnerDriverDeviationMedia? _video;
  late DateTime _day;
  late TabController _tabs;
  List<PartnerVehicle> _vehicles = const [];
  PartnerVehicle? _vehicle;
  List<DriverRouteDayOption> _routes = const [];
  DriverRouteDayOption? _route;
  RoutePdfCustomer? _customer;
  List<PartnerDriverDeviation> _mine = const [];
  bool _loadingVehicles = false;
  bool _loadingRoutes = true;
  bool _loadingMine = true;
  bool _submitting = false;
  String? _routeError;
  String? _mineError;

  bool get _owner => widget.isOwnerMode;
  bool get _pickVehicle => widget.isOwnerMode || widget.isStaffMode;
  bool get _firmMine => widget.isOwnerMode;

  String? get _activeVehicleId =>
      _vehicle?.id ?? widget.profile.partnerVehicleId;

  @override
  void initState() {
    super.initState();
    _day = _dateOnly(DateTime.now());
    _tabs = TabController(length: 2, vsync: this);
    if (_pickVehicle) {
      _loadVehicles();
    } else {
      _loadRoutes();
    }
    _loadMine();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _orderRefCtrl.dispose();
    _customerSearchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  List<RoutePdfCustomer> get _filteredCustomers {
    final all = _route?.customers ?? const [];
    final q = _customerSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((c) {
      final bilag = (c.salesOrder ?? '').toLowerCase();
      final fu = (c.freightUnit ?? '').toLowerCase();
      return c.name.toLowerCase().contains(q) ||
          bilag.contains(q) ||
          fu.contains(q) ||
          '${c.sequence}'.contains(q) ||
          (c.addressHint ?? '').toLowerCase().contains(q) ||
          (c.postalCode ?? '').contains(q);
    }).toList(growable: false);
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _loadingVehicles = true;
      _routeError = null;
    });
    try {
      final vehicles = await PartnerService.fetchVehicles(
        widget.partner.id,
        activeOnly: true,
      );
      final maviOnly = vehicles
          .where(PartnerService.isMaviFleetVehicle)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _vehicles = maviOnly;
        _loadingVehicles = false;
        if (maviOnly.length == 1) {
          _vehicle = maviOnly.first;
        }
      });
      if (maviOnly.length == 1) {
        await _loadRoutes();
      } else {
        setState(() => _loadingRoutes = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVehicles = false;
        _loadingRoutes = false;
        _routeError = 'Kunne ikke hente biler: $e';
      });
    }
  }

  Future<void> _loadRoutes() async {
    final vehicleId = _activeVehicleId;
    if (vehicleId == null) {
      setState(() {
        _loadingRoutes = false;
        _routeError = _pickVehicle
            ? 'Velg hvilken bil/MAVI-rute avviket gjelder.'
            : 'Kontoen er ikke knyttet til en MAVI-bil.';
        _routes = const [];
        _route = null;
        _customer = null;
      });
      return;
    }
    setState(() {
      _loadingRoutes = true;
      _routeError = null;
      _routes = const [];
      _route = null;
      _customer = null;
      _orderRefCtrl.clear();
      _customerSearchCtrl.clear();
    });
    try {
      final options = await PartnerService.fetchDriverRouteOptionsForDay(
        companyId: widget.partner.companyId,
        partnerVehicleId: vehicleId,
        day: _day,
      );
      if (!mounted) return;
      setState(() {
        _routes = options;
        _loadingRoutes = false;
        if (options.isEmpty) {
          _routeError =
              'Ingen ruter funnet ${DateFormat('d. MMMM', 'nb').format(_day)}.';
        } else if (options.length == 1) {
          _selectRoute(options.first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRoutes = false;
        _routeError = 'Kunne ikke hente ruter: $e';
      });
    }
  }

  void _selectVehicle(PartnerVehicle vehicle) {
    setState(() {
      _vehicle = vehicle;
      _route = null;
      _customer = null;
    });
    _loadRoutes();
  }

  void _selectRoute(DriverRouteDayOption option) {
    setState(() {
      _route = option;
      _customer = null;
      _orderRefCtrl.clear();
      _customerSearchCtrl.clear();
    });
  }

  Future<void> _loadMine() async {
    setState(() {
      _loadingMine = true;
      _mineError = null;
    });
    try {
      final items = await PartnerDriverDeviationService.listMine(
        companyId: widget.partner.companyId,
        partnerId: widget.partner.id,
        firmWide: _firmMine,
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
    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 30)),
      );
      if (picked == null || !mounted) return;
      setState(() => _day = _dateOnly(picked));
      await _loadRoutes();
    } catch (e) {
      if (mounted) {
        _message('Kunne ikke åpne datovelger: $e', error: true);
      }
    }
  }

  Future<void> _setDay(DateTime day) async {
    setState(() => _day = _dateOnly(day));
    await _loadRoutes();
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

  void _onCustomerPicked(RoutePdfCustomer customer) {
    final bilag = PartnerDriverDeviationRefs.primaryBilag(
      salesOrder: customer.salesOrder,
      freightRaw: customer.freightUnit,
    );
    setState(() {
      _customer = customer;
      if (bilag != null) _orderRefCtrl.text = bilag;
    });
  }

  Future<void> _submit() async {
    final customer = _customer;
    final route = _route;
    final vehicleId = _activeVehicleId;
    final comment = _commentCtrl.text.trim();
    if (vehicleId == null) {
      _message('Velg bil først.');
      return;
    }
    if (route == null) {
      _message('Velg hvilken rute/last avviket gjelder.');
      return;
    }
    if (customer == null) {
      _message('Velg en kunde fra ruten.');
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
          'Fant ikke bilagsnummer (starter med 2). Skriv inn bilag manuelt.',
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
        routeShareId: route.route.id,
        customerName: customer.name,
        freightUnit: freightStored.isNotEmpty ? freightStored : customerRef,
        customerRef: customerRef,
        orderRef: bilag,
        comment: comment,
        reporterName: widget.profile.fullName,
        images: _images,
        videos: _video == null ? const [] : [_video!],
      );
      if (!mounted) return;
      _commentCtrl.clear();
      _orderRefCtrl.clear();
      _customerSearchCtrl.clear();
      setState(() {
        _images.clear();
        _video = null;
        _customer = null;
      });
      _message('Avviket er sendt til MAVI.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_owner ? 'Avvik' : 'Meld avvik'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Meld'),
            Tab(text: _mine.isEmpty ? 'Mine' : 'Mine (${_mine.length})'),
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
    final customers = _filteredCustomers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Meld rute-/kundeavvik',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          _pickVehicle
              ? 'Velg bil → dato → rute/last → kunde → send. Går til MAVI.'
              : '1) Dato  2) Rute/last  3) Kunde  4) Send',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        if (_pickVehicle) ...[
          const SizedBox(height: 16),
          const Text(
            'Bil / MAVI',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_loadingVehicles)
            const Padding(
              padding: EdgeInsets.all(16),
              child: DriftProLoadingCenter(),
            )
          else if (_vehicles.isEmpty)
            const Text(
              'Ingen aktive biler i firmaet.',
              style: TextStyle(color: Colors.orange),
            )
          else
            ..._vehicles.map((v) {
              final selected = _vehicle?.id == v.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: DriftProTheme.primaryGreen,
                    ),
                    title: Text(
                      v.unitCode,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [
                        if (v.registrationNumber.trim().isNotEmpty)
                          v.registrationNumber.trim(),
                        if ((v.driverName ?? '').trim().isNotEmpty)
                          v.driverName!.trim(),
                      ].join(' · '),
                    ),
                    onTap: () => _selectVehicle(v),
                  ),
                ),
              );
            }),
        ],
        const SizedBox(height: 14),
        const Text(
          'Dato',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setDay(now),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _sameDay(_day, now)
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                      : null,
                  foregroundColor: _sameDay(_day, now)
                      ? DriftProTheme.primaryGreen
                      : null,
                ),
                child: const Text('I dag'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setDay(yesterday),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _sameDay(_day, yesterday)
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                      : null,
                  foregroundColor: _sameDay(_day, yesterday)
                      ? DriftProTheme.primaryGreen
                      : null,
                ),
                child: const Text('I går'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.tonalIcon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              'Velg dato · ${DateFormat('d. MMMM yyyy', 'nb').format(_day)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Rute / last',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (_loadingRoutes)
          const Padding(
            padding: EdgeInsets.all(20),
            child: DriftProLoadingCenter(),
          )
        else if (_routeError != null)
          Text(_routeError!, style: const TextStyle(color: Colors.orange))
        else
          ..._routes.map((opt) {
            final selected = _route?.route.id == opt.route.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selected
                    ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _selectRoute(opt),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: DriftProTheme.primaryGreen,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt.displayTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                opt.subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                DateFormat('d. MMMM yyyy', 'nb')
                                    .format(opt.route.shareDate),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        if (_route != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Kunde',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customerSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Søk navn, bilag, adresse…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _customerSearchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _customerSearchCtrl.clear();
                        setState(() {});
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (customers.isEmpty)
            Text(
              _route!.customers.isEmpty
                  ? 'Ingen kunder i denne rute-PDF-en.'
                  : 'Ingen treff — prøv et annet søk.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          else
            ...customers.map((c) {
              final selected = _customer?.sequence == c.sequence &&
                  _customer?.name == c.name;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: selected
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                      child: Text(
                        '${c.sequence}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: DriftProTheme.primaryGreen,
                        ),
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _customerLabel(c),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check_circle,
                            color: DriftProTheme.primaryGreen,
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => _onCustomerPicked(c),
                  ),
                ),
              );
            }),
        ],
        if (_customer != null) ...[
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
            minLines: 5,
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
          const SizedBox(height: 16),
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
                label: Text(
                  _video == null ? 'Video fra galleri' : 'Video valgt',
                ),
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
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
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
              title: Text(
                _video!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () => setState(() => _video = null),
                icon: const Icon(Icons.close),
              ),
            ),
          const SizedBox(height: 22),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildArchiveTab() {
    if (_loadingMine) return const DriftProLoadingCenter();
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
              _firmMine
                  ? 'Ingen avvik i firmaet ennå'
                  : 'Du har ikke sendt noen avvik ennå',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
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
          final media = item.imageUrls.length + item.videoUrls.length;
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
                    if (_firmMine) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Sendt av ${item.reporterLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
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
