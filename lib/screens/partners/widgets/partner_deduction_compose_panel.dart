import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/partner_deduction_logiqrma_descriptions.dart';
import '../../../core/constants/partner_deduction_templates.dart';
import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/storage/company_file_storage.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import 'partner_deduction_logiqrma_panel.dart';
import 'partner_modern_ui.dart';

class PartnerDeductionComposePanel extends StatefulWidget {
  const PartnerDeductionComposePanel({
    super.key,
    required this.partners,
    required this.onCreated,
    this.initialPartner,
    this.nestedInParentScroll = false,
  });

  final List<Partner> partners;
  final VoidCallback onCreated;
  final Partner? initialPartner;
  final bool nestedInParentScroll;

  @override
  State<PartnerDeductionComposePanel> createState() => _PartnerDeductionComposePanelState();
}

class _PartnerDeductionComposePanelState extends State<PartnerDeductionComposePanel> {
  Partner? _partner;
  PartnerDeductionTemplate? _template;
  final _commentCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '500');
  final _logiqrmaCaseCtrl = TextEditingController();
  final _voucherCtrl = TextEditingController();
  final _logisticsDescCtrl = TextEditingController();
  bool _notifySms = true;
  bool _notifyEmail = true;
  bool _submitting = false;
  String? _companyId;
  final List<PartnerDeductionPendingEvidence> _evidence = [];
  bool? _dropboxConnected;
  String _partnerQuery = '';
  String? _selectedLogisticsDescription;

  @override
  void initState() {
    super.initState();
    _partner = widget.initialPartner;
    _loadCompany();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _amountCtrl.dispose();
    _logiqrmaCaseCtrl.dispose();
    _voucherCtrl.dispose();
    _logisticsDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCompany() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    final dropbox = await CompanyFileStorage.isDropboxConnected();
    if (mounted) setState(() {
      _companyId = cid;
      _dropboxConnected = dropbox;
    });
  }

  List<Partner> get _activePartners {
    final q = _partnerQuery.trim().toLowerCase();
    return widget.partners
        .where((p) => p.isActive)
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _pickEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'mp4', 'mov', 'webm', 'm4v'],
      withData: true,
    );
    if (result == null) return;
    final added = <PartnerDeductionPendingEvidence>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      if (bytes.length > 80 * 1024 * 1024) continue;
      added.add(PartnerDeductionPendingEvidence(
        fileName: f.name,
        bytes: bytes,
        extension: f.extension,
      ));
    }
    if (added.isEmpty) return;
    setState(() => _evidence.addAll(added));
  }

  double get _amount {
    final v = double.tryParse(_amountCtrl.text.replaceAll(',', '.').trim());
    return v ?? kPartnerDeductionDefaultAmount;
  }

  String? _previewSms() {
    final p = _partner;
    final t = _template;
    if (p == null || t == null) return null;
    return PartnerDeductionService.buildSmsBody(
      partner: p,
      template: t,
      amountNok: _amount,
      comment: _commentCtrl.text.trim(),
      logiqrmaCaseNumber: _logiqrmaCaseCtrl.text.trim(),
      voucherNumber: _voucherCtrl.text.trim(),
      logiqrmaComment: _logisticsDescCtrl.text.trim(),
    ).replaceAll('{sak}', 'BOT-${DateTime.now().year}-0001');
  }

  Future<void> _submit() async {
    final cid = _companyId;
    final partner = _partner;
    final template = _template;
    if (cid == null || partner == null || template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg bedrift og mal')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrer trekk'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bedrift: ${partner.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Mal: ${template.title}'),
              Text('Beløp: kr ${_amount.toStringAsFixed(0)},-'),
              if (_notifySms && (partner.phone?.isNotEmpty ?? false))
                Text('SMS: ${partner.phone}'),
              if (_notifyEmail && (partner.email?.isNotEmpty ?? false))
                Text('E-post: ${partner.email}'),
              if (_evidence.isNotEmpty)
                Text('${_evidence.length} bevisfil(er) lagres permanent'),
              if (_logiqrmaCaseCtrl.text.trim().isNotEmpty)
                Text('LogiqRMA saksnummer: ${_logiqrmaCaseCtrl.text.trim()}'),
              if (_voucherCtrl.text.trim().isNotEmpty)
                Text('Bilag: ${_voucherCtrl.text.trim()}'),
              if (_logisticsDescCtrl.text.trim().isNotEmpty)
                Text('LogiqRMA kommentar: ${_logisticsDescCtrl.text.trim()}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrer sak')),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() => _submitting = true);
    final result = await PartnerDeductionService.createCase(
      companyId: cid,
      partner: partner,
      template: template,
      amountNok: _amount,
      comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      logiqrmaCaseNumber: _logiqrmaCaseCtrl.text.trim().isEmpty ? null : _logiqrmaCaseCtrl.text.trim(),
      voucherNumber: _voucherCtrl.text.trim().isEmpty ? null : _voucherCtrl.text.trim(),
      logisticsDescription: _logisticsDescCtrl.text.trim().isEmpty ? null : _logisticsDescCtrl.text.trim(),
      notifySms: _notifySms,
      notifyEmail: _notifyEmail,
      evidence: _evidence,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result.success || result.caseRow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Kunne ikke registrere sak')),
      );
      return;
    }

    final row = result.caseRow!;
    widget.onCreated();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
        title: const Text('Sak registrert'),
        content: Text(
          'Sak ${row.caseNumber} er opprettet med trekk på kr ${row.amountNok.toStringAsFixed(0)},-.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    setState(() {
      _commentCtrl.clear();
      _amountCtrl.text = '500';
      _logiqrmaCaseCtrl.clear();
      _voucherCtrl.clear();
      _logisticsDescCtrl.clear();
      _selectedLogisticsDescription = null;
      _evidence.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);

    final sakChildren = <Widget>[
        if (_dropboxConnected == false)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber),
            ),
            child: const Text(
              'Skylagring er ikke koblet — bevis lagres midlertidig inntil fillagring er aktivert under Innstillinger.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        _sectionTitle('1. Velg bedrift'),
        const SizedBox(height: 8),
        if (widget.initialPartner == null)
          TextField(
            decoration: InputDecoration(
              hintText: 'Søk bedrift …',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _partnerQuery = v),
          ),
        if (widget.initialPartner == null) const SizedBox(height: 8),
        DropdownButtonFormField<Partner>(
          value: _partner,
          decoration: InputDecoration(
            labelText: 'Samarbeidspartner',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.apartment_outlined),
          ),
          items: [
            for (final p in _activePartners)
              DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _partner = v),
        ),
        if (_partner != null) ...[
          const SizedBox(height: 8),
          _contactRow(_partner!),
        ],
        const SizedBox(height: 20),
        _sectionTitle('2. Velg mal'),
        const SizedBox(height: 8),
        ...kPartnerDeductionTemplates.map((t) => _templateCard(t)),
        const SizedBox(height: 20),
        _sectionTitle('3. Beløp og kommentar'),
        const SizedBox(height: 8),
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Trekkbeløp (NOK)',
            hintText: '500',
            prefixIcon: const Icon(Icons.payments_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            helperText: 'Standard trekk er kr ${kPartnerDeductionDefaultAmount.toInt()},-',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Kommentar (valgfritt)',
            hintText: 'Presiser dato, kjøretøy, hendelse …',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        _sectionTitle('4. LogiqRMA (valgfritt)'),
        const SizedBox(height: 8),
        PartnerDeductionLogiqRmaPanel(
          caseNumberCtrl: _logiqrmaCaseCtrl,
          voucherCtrl: _voucherCtrl,
          commentCtrl: _logisticsDescCtrl,
          selectedComment: _selectedLogisticsDescription,
          suggestedComment: _template == null ? null : logiqrmaDescriptionForTemplate(_template!.id),
          onCommentSelected: (v) => setState(() => _selectedLogisticsDescription = v),
        ),
        const SizedBox(height: 20),
        _sectionTitle('5. Bevis (bilde/video)'),
        const SizedBox(height: 8),
        Text(
          'Last opp bilder eller video som dokumentasjon. Filene lagres permanent '
          'og vises for bil-eier i portalen.',
          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context), height: 1.4),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickEvidence,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Legg ved bilde eller video'),
        ),
        if (_evidence.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _evidence.length; i++)
                Chip(
                  avatar: Icon(
                    PartnerDeductionService.isVideoFileName(_evidence[i].fileName)
                        ? Icons.videocam_outlined
                        : Icons.image_outlined,
                    size: 16,
                  ),
                  label: Text(_evidence[i].fileName, style: const TextStyle(fontSize: 11)),
                  onDeleted: () => setState(() => _evidence.removeAt(i)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _sectionTitle('6. Varsle bedrift'),
        SwitchListTile(
          value: _notifySms,
          onChanged: (_partner?.phone?.isNotEmpty ?? false)
              ? (v) => setState(() => _notifySms = v)
              : null,
          title: const Text('Send SMS'),
          subtitle: Text(_partner?.phone?.isNotEmpty == true ? _partner!.phone! : 'Mangler telefon'),
        ),
        SwitchListTile(
          value: _notifyEmail,
          onChanged: (_partner?.email?.isNotEmpty ?? false)
              ? (v) => setState(() => _notifyEmail = v)
              : null,
          title: const Text('Send e-post'),
          subtitle: Text(_partner?.email?.isNotEmpty == true ? _partner!.email! : 'Mangler e-post'),
        ),
        if (_previewSms() != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.driftColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PartnerModernUi.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SMS-forhåndsvisning', style: DriftProTheme.labelSm),
                const SizedBox(height: 6),
                Text(_previewSms()!, style: const TextStyle(fontSize: 12, height: 1.45)),
              ],
            ),
          ),
        ],
    ];

    final children = <Widget>[
      ...sakChildren,
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: _submitting || _partner == null || _template == null ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.gavel_rounded),
          label: Text(
            _submitting
                ? 'Registrerer …'
                : 'Registrer sak · ${money.format(_amount)}',
          ),
        ),
      ),
    ];

    if (widget.nestedInParentScroll) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: children,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: DriftProTheme.labelLg.copyWith(
        color: PartnerModernUi.textPrimary(context),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _contactRow(Partner p) {
    return Row(
      children: [
        if (p.phone?.isNotEmpty == true)
          Chip(
            avatar: const Icon(Icons.phone, size: 16),
            label: Text(p.phone!, style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
          ),
        if (p.email?.isNotEmpty == true) ...[
          const SizedBox(width: 6),
          Expanded(
            child: Chip(
              avatar: const Icon(Icons.email_outlined, size: 16),
              label: Text(p.email!, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }

  Widget _templateCard(PartnerDeductionTemplate t) {
    final selected = _template?.id == t.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            final suggested = logiqrmaDescriptionForTemplate(t.id);
            setState(() {
              _template = t;
              if (suggested != null && _logisticsDescCtrl.text.trim().isEmpty) {
                _logisticsDescCtrl.text = suggested;
                _selectedLogisticsDescription = suggested;
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? DriftProTheme.primaryGreen
                    : PartnerModernUi.border(context),
                width: selected ? 2 : 1,
              ),
              color: selected
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.06)
                  : PartnerModernUi.surface(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconFor(t.iconName),
                  color: selected ? DriftProTheme.primaryGreen : PartnerModernUi.muted(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                      Text(
                        t.category,
                        style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.shortDescription,
                        style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context), height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: DriftProTheme.primaryGreen, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) => switch (name) {
        'delete_outline' => Icons.delete_outline,
        'checkroom_outlined' => Icons.checkroom_outlined,
        'local_parking_outlined' => Icons.local_parking_outlined,
        'route_outlined' => Icons.route_outlined,
        'directions_car_outlined' => Icons.directions_car_outlined,
        'inventory_2_outlined' => Icons.inventory_2_outlined,
        'description_outlined' => Icons.description_outlined,
        'cleaning_services_outlined' => Icons.cleaning_services_outlined,
        'health_and_safety_outlined' => Icons.health_and_safety_outlined,
        'forum_outlined' => Icons.forum_outlined,
        'record_voice_over_outlined' => Icons.record_voice_over_outlined,
        _ => Icons.gavel_outlined,
      };
}
