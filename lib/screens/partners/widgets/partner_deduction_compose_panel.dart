import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/partner_deduction_logiqrma_descriptions.dart';
import '../../../core/constants/partner_deduction_templates.dart';
import '../../../core/layout/web_layout.dart';
import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/storage/company_file_storage.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import 'partner_deduction_hub_ui.dart';
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
  static const _quickAmounts = [500, 750, 1000, 1500];

  Partner? _partner;
  PartnerDeductionTemplate? _template;
  final _commentCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '500');
  final _logiqrmaCaseCtrl = TextEditingController();
  final _voucherCtrl = TextEditingController();
  final _logisticsDescCtrl = TextEditingController();
  bool _notifySms = true;
  bool _notifyEmail = true;
  bool _notifyPush = true;
  bool _submitting = false;
  bool _logiqRmaExpanded = false;
  bool _previewExpanded = false;
  String? _companyId;
  final List<PartnerDeductionPendingEvidence> _evidence = [];
  bool? _dropboxConnected;
  String _partnerQuery = '';
  String? _selectedLogisticsDescription;
  String? _categoryFilter;

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
    if (mounted) {
      setState(() {
        _companyId = cid;
        _dropboxConnected = dropbox;
      });
    }
  }

  List<Partner> get _activePartners {
    final q = _partnerQuery.trim().toLowerCase();
    return widget.partners
        .where((p) => p.isActive)
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<String> get _categories {
    final cats = kPartnerDeductionTemplates.map((t) => t.category).toSet().toList()
      ..sort();
    return cats;
  }

  List<PartnerDeductionTemplate> get _filteredTemplates {
    final cat = _categoryFilter;
    if (cat == null) return kPartnerDeductionTemplates;
    return kPartnerDeductionTemplates.where((t) => t.category == cat).toList();
  }

  String get _previewCaseNumber {
    final year = DateTime.now().year;
    final code = _partnerCaseCode ?? 'XXXX';
    return 'BOT-$code-$year-0001';
  }

  String? get _partnerCaseCode {
    final p = _partner;
    if (p == null) return null;
    final stored = p.caseCode?.trim();
    if (stored != null && stored.isNotEmpty) return stored.toUpperCase();
    final label = (p.tradeName?.trim().isNotEmpty == true ? p.tradeName! : p.name).toUpperCase();
    final match = RegExp(r'[A-ZÆØÅ0-9]+').firstMatch(label);
    final word = match?.group(0);
    if (word == null || word.length < 2) return null;
    return word.length > 8 ? word.substring(0, 8) : word;
  }

  bool get _canSubmit => !_submitting && _partner != null && _template != null;

  int get _completedSteps {
    var n = 0;
    if (_partner != null) n++;
    if (_template != null) n++;
    if (_amount > 0) n++;
    return n;
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
    ).replaceAll('{sak}', _previewCaseNumber);
  }

  void _selectTemplate(PartnerDeductionTemplate t) {
    final suggested = logiqrmaDescriptionForTemplate(t.id);
    setState(() {
      _template = t;
      if (suggested != null && _logisticsDescCtrl.text.trim().isEmpty) {
        _logisticsDescCtrl.text = suggested;
        _selectedLogisticsDescription = suggested;
      }
    });
  }

  void _setQuickAmount(int amount) {
    _amountCtrl.text = amount.toString();
    setState(() {});
  }

  Future<void> _submit() async {
    final cid = _companyId;
    final partner = _partner;
    final template = _template;
    if (cid == null || partner == null || template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg bedrift og årsak først')),
      );
      return;
    }

    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.gavel_rounded, color: PartnerDeductionHubUi.accent, size: 36),
        title: const Text('Bekreft og send'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _confirmRow('Bedrift', partner.name),
              _confirmRow('Årsak', template.title),
              _confirmRow('Beløp', money.format(_amount)),
              _confirmRow('Saksnr.', _previewCaseNumber),
              if (_commentCtrl.text.trim().isNotEmpty)
                _confirmRow('Kommentar', _commentCtrl.text.trim()),
              const Divider(height: 24),
              const Text('Varsling', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              if (_notifySms && (partner.phone?.isNotEmpty ?? false))
                _confirmRow('SMS', partner.phone!),
              if (_notifyEmail && (partner.email?.isNotEmpty ?? false))
                _confirmRow('E-post', partner.email!),
              if (_notifyPush) _confirmRow('Push', 'Til bedriftsansvarlig i appen'),
              if (!_notifySms && !_notifyEmail && !_notifyPush)
                Text(
                  'Ingen varsler valgt',
                  style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(ctx)),
                ),
              if (_evidence.isNotEmpty) ...[
                const SizedBox(height: 12),
                _confirmRow('Bevis', '${_evidence.length} fil(er)'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Gå tilbake')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PartnerDeductionHubUi.accent),
            child: const Text('Send trekk'),
          ),
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
      notifyPush: _notifyPush,
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
        title: const Text('Trekk registrert'),
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
      _template = null;
      _evidence.clear();
      _categoryFilter = null;
    });
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final wide = WebLayout.isWide(context, minWidth: 640);
    final content = _buildScrollContent(context, money, wide);
    final bottomBar = _buildBottomBar(context, money);

    if (widget.nestedInParentScroll) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          bottomBar,
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: content),
        bottomBar,
      ],
    );
  }

  Widget _buildScrollContent(BuildContext context, NumberFormat money, bool wide) {
    final scroll = ListView(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 16, 8, wide ? 20 : 16, 16),
      children: [
        _buildIntro(context),
        if (_dropboxConnected == false) ...[
          const SizedBox(height: 12),
          _buildWarningBanner(context),
        ],
        const SizedBox(height: 16),
        _buildPartnerCard(context),
        const SizedBox(height: 14),
        _buildTemplateCard(context, wide),
        const SizedBox(height: 14),
        _buildAmountCard(context, money),
        const SizedBox(height: 14),
        _buildLogiqRmaCard(context),
        const SizedBox(height: 14),
        _buildEvidenceCard(context),
        const SizedBox(height: 14),
        _buildNotifyCard(context),
        const SizedBox(height: 14),
        _buildPreviewCard(context),
        const SizedBox(height: 8),
      ],
    );

    return PartnerDeductionHubUi.pageShell(context: context, child: scroll);
  }

  Widget _buildIntro(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerDeductionHubUi.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartnerDeductionHubUi.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          _stepRing(context, _completedSteps, 3),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sett opp trekket før sending',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Velg bedrift, årsak og beløp. Alt kan endres helt til du trykker «Send trekk».',
                  style: TextStyle(fontSize: 12, height: 1.4, color: PartnerModernUi.muted(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRing(BuildContext context, int done, int total) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: done / total,
            strokeWidth: 3,
            backgroundColor: PartnerModernUi.border(context),
            color: PartnerDeductionHubUi.accent,
          ),
          Text('$done/$total', style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Skylagring er ikke koblet — bevis lagres midlertidig til fillagring er aktivert.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerCard(BuildContext context) {
    return _ComposeSection(
      icon: Icons.apartment_rounded,
      title: 'Bedrift',
      subtitle: 'Hvem skal få trekket?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.initialPartner == null) ...[
            TextField(
              decoration: InputDecoration(
                hintText: 'Søk etter navn …',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _partnerQuery = v),
            ),
            const SizedBox(height: 10),
          ],
          if (widget.initialPartner != null && _partner != null)
            _selectedPartnerTile(context, _partner!)
          else
            DropdownButtonFormField<Partner>(
              value: _partner,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Velg samarbeidspartner',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.business_outlined),
              ),
              items: [
                for (final p in _activePartners)
                  DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _partner = v),
            ),
          if (_partner != null && widget.initialPartner == null) ...[
            const SizedBox(height: 10),
            _selectedPartnerTile(context, _partner!),
          ],
        ],
      ),
    );
  }

  Widget _selectedPartnerTile(BuildContext context, Partner p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.driftColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (p.phone?.isNotEmpty == true)
                _contactChip(Icons.phone_rounded, p.phone!, available: true),
              if (p.email?.isNotEmpty == true)
                _contactChip(Icons.mail_outline_rounded, p.email!, available: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Saksnummer: $_previewCaseNumber',
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _contactChip(IconData icon, String label, {required bool available}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: available ? DriftProTheme.primaryGreen.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: available ? DriftProTheme.primaryGreen : Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, bool wide) {
    return _ComposeSection(
      icon: Icons.category_rounded,
      title: 'Årsak',
      subtitle: 'Velg hva trekket gjelder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip(context, label: 'Alle', selected: _categoryFilter == null, onTap: () {
                  setState(() => _categoryFilter = null);
                }),
                for (final cat in _categories)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _categoryChip(
                      context,
                      label: cat,
                      selected: _categoryFilter == cat,
                      onTap: () => setState(() => _categoryFilter = cat),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = wide && constraints.maxWidth > 480 ? 2 : 1;
              final templates = _filteredTemplates;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: cols == 2 ? 2.6 : 2.35,
                ),
                itemCount: templates.length,
                itemBuilder: (context, i) => _templateTile(context, templates[i]),
              );
            },
          ),
          if (_template != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PartnerDeductionHubUi.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PartnerDeductionHubUi.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: PartnerDeductionHubUi.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _template!.detailParagraph,
                      style: TextStyle(fontSize: 12, height: 1.45, color: PartnerModernUi.textPrimary(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: PartnerDeductionHubUi.accent.withValues(alpha: 0.15),
      checkmarkColor: PartnerDeductionHubUi.accent,
      side: BorderSide(color: selected ? PartnerDeductionHubUi.accent : PartnerModernUi.border(context)),
    );
  }

  Widget _templateTile(BuildContext context, PartnerDeductionTemplate t) {
    final selected = _template?.id == t.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectTemplate(t),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? PartnerDeductionHubUi.accent : PartnerModernUi.border(context),
              width: selected ? 2 : 1,
            ),
            color: selected
                ? PartnerDeductionHubUi.accent.withValues(alpha: 0.07)
                : PartnerModernUi.surface(context),
          ),
          child: Row(
            children: [
              Icon(
                _iconFor(t.iconName),
                size: 20,
                color: selected ? PartnerDeductionHubUi.accent : PartnerModernUi.muted(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    Text(
                      t.category,
                      style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: PartnerDeductionHubUi.accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountCard(BuildContext context, NumberFormat money) {
    final selectedQuick = int.tryParse(_amountCtrl.text.trim());
    return _ComposeSection(
      icon: Icons.payments_rounded,
      title: 'Beløp og kommentar',
      subtitle: 'Standard er kr ${kPartnerDeductionDefaultAmount.toInt()},-',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in _quickAmounts)
                ChoiceChip(
                  label: Text('kr $a,-'),
                  selected: selectedQuick == a,
                  onSelected: (_) => _setQuickAmount(a),
                  selectedColor: PartnerDeductionHubUi.accent.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontWeight: selectedQuick == a ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Eget beløp (NOK)',
              prefixIcon: const Icon(Icons.edit_outlined),
              suffixText: money.format(_amount).replaceAll('kr', '').trim(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Tilleggskommentar (valgfritt)',
              hintText: 'Dato, kjøretøy, hendelse …',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildLogiqRmaCard(BuildContext context) {
    final hasData = _logiqrmaCaseCtrl.text.isNotEmpty ||
        _voucherCtrl.text.isNotEmpty ||
        _logisticsDescCtrl.text.isNotEmpty;
    return _ComposeSection(
      icon: Icons.link_rounded,
      title: 'LogiqRMA',
      subtitle: 'Valgfritt — koble til sak i LogiqRMA',
      trailing: hasData
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Fylt ut', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            )
          : null,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _logiqRmaExpanded = !_logiqRmaExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _logiqRmaExpanded ? 'Skjul felter' : 'Vis LogiqRMA-felter',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PartnerDeductionHubUi.accent,
                      ),
                    ),
                  ),
                  Icon(
                    _logiqRmaExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: PartnerDeductionHubUi.accent,
                  ),
                ],
              ),
            ),
          ),
          if (_logiqRmaExpanded) ...[
            const SizedBox(height: 8),
            PartnerDeductionLogiqRmaPanel(
              caseNumberCtrl: _logiqrmaCaseCtrl,
              voucherCtrl: _voucherCtrl,
              commentCtrl: _logisticsDescCtrl,
              selectedComment: _selectedLogisticsDescription,
              suggestedComment: _template == null ? null : logiqrmaDescriptionForTemplate(_template!.id),
              onCommentSelected: (v) => setState(() => _selectedLogisticsDescription = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEvidenceCard(BuildContext context) {
    return _ComposeSection(
      icon: Icons.photo_library_rounded,
      title: 'Bevis',
      subtitle: 'Bilde eller video som dokumentasjon',
      trailing: _evidence.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: PartnerDeductionHubUi.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${_evidence.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _pickEvidence,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Legg ved fil'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _evidence.length; i++)
                  InputChip(
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
        ],
      ),
    );
  }

  Widget _buildNotifyCard(BuildContext context) {
    final p = _partner;
    return _ComposeSection(
      icon: Icons.notifications_active_rounded,
      title: 'Varsling',
      subtitle: 'Velg hvordan bedriften skal få beskjed',
      child: Column(
        children: [
          _notifyTile(
            context,
            icon: Icons.sms_rounded,
            title: 'SMS',
            subtitle: p?.phone?.isNotEmpty == true ? p!.phone! : 'Ingen telefon registrert',
            enabled: p?.phone?.isNotEmpty ?? false,
            value: _notifySms,
            onChanged: (v) => setState(() => _notifySms = v),
          ),
          const SizedBox(height: 8),
          _notifyTile(
            context,
            icon: Icons.email_rounded,
            title: 'E-post',
            subtitle: p?.email?.isNotEmpty == true ? p!.email! : 'Ingen e-post registrert',
            enabled: p?.email?.isNotEmpty ?? false,
            value: _notifyEmail,
            onChanged: (v) => setState(() => _notifyEmail = v),
          ),
          const SizedBox(height: 8),
          _notifyTile(
            context,
            icon: Icons.phone_iphone_rounded,
            title: 'Push i appen',
            subtitle: 'Til bedriftsansvarlig med DriftPro (partnerportal)',
            enabled: true,
            value: _notifyPush,
            onChanged: (v) => setState(() => _notifyPush = v),
          ),
        ],
      ),
    );
  }

  Widget _notifyTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: context.driftColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value && enabled ? PartnerDeductionHubUi.accent.withValues(alpha: 0.4) : PartnerModernUi.border(context),
          ),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled ? value : false,
          onChanged: enabled ? onChanged : null,
          secondary: Icon(icon, color: enabled ? PartnerDeductionHubUi.accent : PartnerModernUi.muted(context)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final sms = _previewSms();
    if (sms == null) {
      return _ComposeSection(
        icon: Icons.preview_rounded,
        title: 'Forhåndsvisning',
        subtitle: 'Velg bedrift og årsak for å se melding',
        child: Text(
          'SMS- og e-posttekst genereres automatisk ut fra valgene dine.',
          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context), height: 1.4),
        ),
      );
    }

    return _ComposeSection(
      icon: Icons.preview_rounded,
      title: 'Forhåndsvisning',
      subtitle: 'Slik ser varslingen ut',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _previewExpanded = !_previewExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _previewExpanded ? 'Skjul melding' : 'Vis full SMS-tekst',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PartnerDeductionHubUi.accent,
                      ),
                    ),
                  ),
                  Icon(
                    _previewExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: PartnerDeductionHubUi.accent,
                  ),
                ],
              ),
            ),
          ),
          if (_previewExpanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.driftColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PartnerModernUi.border(context)),
              ),
              child: Text(sms, style: const TextStyle(fontSize: 12, height: 1.5)),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              sms.length > 120 ? '${sms.substring(0, 120)}…' : sms,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.45, color: PartnerModernUi.muted(context)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, NumberFormat money) {
    final partner = _partner;
    final template = _template;
    return Material(
      elevation: 8,
      color: PartnerModernUi.surface(context),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: PartnerModernUi.border(context))),
          ),
          child: PartnerDeductionHubUi.pageShell(
            context: context,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        partner?.name ?? 'Velg bedrift',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                      Text(
                        template?.title ?? 'Velg årsak',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                      ),
                      Text(
                        money.format(_amount),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: PartnerDeductionHubUi.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: PartnerDeductionHubUi.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(_submitting ? 'Sender …' : 'Send trekk'),
                ),
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

class _ComposeSection extends StatelessWidget {
  const _ComposeSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PartnerDeductionHubUi.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: PartnerDeductionHubUi.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: PartnerModernUi.muted(context), height: 1.3),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
