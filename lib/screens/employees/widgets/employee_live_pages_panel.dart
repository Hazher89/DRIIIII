import 'package:flutter/material.dart';

import '../../../core/permissions/access_actions.dart';
import '../../../core/permissions/access_area_catalog.dart';
import '../../../core/permissions/access_normalize.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// Kompakt tilgangsoversikt. Brytere lagres med en gang.
class EmployeeLivePagesPanel extends StatefulWidget {
  const EmployeeLivePagesPanel({
    super.key,
    required this.employee,
    required this.settings,
    required this.onSettings,
  });

  final UserProfile employee;
  final Map<String, dynamic> settings;
  final ValueChanged<Map<String, dynamic>> onSettings;

  @override
  State<EmployeeLivePagesPanel> createState() => _EmployeeLivePagesPanelState();
}

class _EmployeeLivePagesPanelState extends State<EmployeeLivePagesPanel> {
  late AccessSettingsDoc _doc;
  bool _busy = false;
  String? _status;
  final _search = TextEditingController();
  final _title = TextEditingController();
  String _query = '';
  String _filter = 'Alle';
  String? _linkAreaId;
  final Set<String> _open = {};

  static const _groups = <String, List<String>>{
    'Hjem': ['dashboard', 'surveys', 'fravaer', 'avvik', 'stempling'],
    'HMS': ['hms', 'uniform'],
    'Partnere': ['partners'],
    'Mer': ['more'],
  };

  static const _tips = <String, String>{
    'dashboard': 'Forsiden. Av = Hjem forsvinner fra menyen.',
    'surveys': 'Fane for undersøkelser.',
    'surveys.build': 'Lage og endre skjema.',
    'surveys.results': 'Se svar. Uten dette ser man bare egne skjema.',
    'fravaer': 'Ferie og fravær. Av = hele fanen er borte.',
    'fravaer.mine': 'Egne søknader og saldo.',
    'fravaer.team': 'Se kolleger i avdelingen som er borte.',
    'fravaer.godkjenn': 'Godkjenne eller avvise andres søknader.',
    'fravaer.registrer_andre': 'Sende ferie/fravær på vegne av andre.',
    'fravaer.ferie_admin': 'Ferieår, overføring og kvote for hele bedriften.',
    'avvik': 'Avvik og RUH. Vanlige ansatte har dette av.',
    'avvik.nytt': 'Opprette nytt avvik.',
    'avvik.behandle': 'Behandle og lukke andres avvik.',
    'avvik.koordinere': 'Kontrollsenter på tvers av avdelinger.',
    'avvik.admin': 'Tall og admin-oversikt for avvik.',
    'hms': 'HMS-fanen. Underpunkter kan skjules hver for seg.',
    'hms.risiko': 'Risikovurderinger.',
    'hms.sja': 'Sikker jobb-analyse.',
    'hms.vernerunde': 'Vernerunder og sikkerhetsrunder.',
    'hms.risikomatrise': 'Samlet risikomatrise.',
    'hms.utstyr': 'Maskiner og utstyr.',
    'hms.utstyr.admin': 'Endre utstyrsregisteret.',
    'hms.utstyr.service': 'Registrere service.',
    'hms.utstyr.servicehefte': 'Lese servicehefter.',
    'hms.kompetanse': 'Kurs og kompetanse.',
    'hms.dokumenter': 'HMS-dokumenter (DMS).',
    'hms.opplaering': 'Opplæring og SOP.',
    'uniform': 'Uniformkontroll og kamera.',
    'uniform.admin': 'Kamera og innstillinger for uniform.',
    'partners': 'Partner-modulen. Av = hele partnerflaten er borte.',
    'partners.create': 'Opprette ny partner.',
    'partners.edit': 'Endre partnerdata.',
    'partners.delete': 'Slette partner. Sterk handling — GDPR.',
    'partners.admin': 'Full administrasjon av partnere.',
    'partners.fleet': 'Ruter og planlegging.',
    'partners.vehicle_rental': 'Bilutleie.',
    'partners.vehicle_rental.approve': 'Godkjenne utleie.',
    'partners.tabs.oversikt': 'Fanen Oversikt hos partner.',
    'partners.tabs.ruter': 'Fanen Ruter.',
    'partners.tabs.bilkontroll': 'Fanen Bilkontroll.',
    'partners.tabs.dokumenter': 'Fanen Dokumenter.',
    'partners.tabs.loyver': 'Fanen Løyver.',
    'partners.tabs.oppfolging': 'Fanen Oppfølging.',
    'partners.tabs.sms': 'Sende SMS til partner.',
    'partners.tabs.bot_trekk': 'Bot og trekk.',
    'partners.tabs.oppsummering': 'Fanen Oppsummering.',
    'partners.tabs.fri': 'Fanen Fri.',
    'partners.chat': 'Partner-chat.',
    'partners.chat.internal': 'Intern MAVI-chat.',
    'partners.chat.broadcast': 'Melding til alle partnere.',
    'partners.chat.direct': 'Melding til én partner.',
    'partners.chat.moderate': 'Slette og moderere chat.',
    'stempling': 'Stemple inn og ut.',
    'stempling.admin': 'Timeliste og andres stempling.',
    'stempling.mobile': 'Stemple fra mobil og nett.',
    'stempling.innstillinger': 'Kiosk og stemplingsoppsett.',
    'more': 'Mer-fanen er alltid på. Innholdet under kan skjules.',
    'more.profil': 'Egen profil. Bør være på.',
    'more.app_innstillinger': 'Appinnstillinger for bedriften.',
    'more.avdelinger': 'Se avdelinger.',
    'more.ansatte': 'Se ansattlisten.',
    'more.personalmappe': 'Personaldokumenter. Sensitivt — GDPR.',
    'more.varsler': 'Varsler og varselinnstillinger.',
    'more.undersokelser': 'Snarvei til undersøkelser i Mer.',
    'more.whistleblowing': 'Anonym anmeldelse.',
    'more.kiosk': 'Infoskjerm.',
    'more.forside': 'Redigere forside: bilde, video, dokument.',
    'more.work_steps': 'Egne skritt på jobb.',
    'more.work_steps_hub': 'Se andres skritt. Persondata.',
    'more.drive_monitor': 'Sporing av leiebil. Posisjonsdata.',
    'more.partnere': 'Snarvei til partnere i Mer.',
    'more.tilgangskontroll': 'Denne siden. Bare tillitspersoner.',
    'more.brukergodkjenning': 'Godkjenne nye brukere.',
    'more.dropbox': 'Fillagring.',
    'more.vision_cameras': 'Kameraoppsett.',
    'more.vision_events': 'Kamerahendelser og video.',
    'admin.ansatte_rediger': 'Endre ansatt og tilganger.',
    'admin.avdelinger_rediger': 'Opprette og endre avdelinger.',
  };

  @override
  void initState() {
    super.initState();
    _doc = AccessSettingsDoc.fromJson(widget.settings);
    _linkAreaId = _linkChoices.isEmpty ? null : _linkChoices.first.id;
  }

  @override
  void didUpdateWidget(EmployeeLivePagesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings && !_busy) {
      _doc = AccessSettingsDoc.fromJson(widget.settings);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    super.dispose();
  }

  List<AccessAreaDef> get _linkChoices => AccessAreaCatalog.areas
      .where((a) => a.routePath != null && a.routePath!.startsWith('/'))
      .toList();

  bool _on(AccessAreaDef area) => _doc.get(area.id, AccessAction.view);

  bool _lockedArea(AccessAreaDef area) => area.id == 'more';

  String _rootOf(AccessAreaDef area) {
    var id = area.id;
    while (AccessAreaCatalog.byId[id]?.parentId != null) {
      id = AccessAreaCatalog.byId[id]!.parentId!;
    }
    return id;
  }

  bool _inFilter(AccessAreaDef area) {
    if (_filter == 'På') return _on(area);
    if (_filter == 'Av') return !_on(area) && !_lockedArea(area);
    if (_filter == 'Alle') return true;
    final roots = _groups[_filter] ?? const <String>[];
    return roots.contains(_rootOf(area));
  }

  bool _matches(AccessAreaDef area) {
    if (!_inFilter(area)) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final tip = (_tips[area.id] ?? '').toLowerCase();
    return area.title.toLowerCase().contains(q) ||
        area.id.toLowerCase().contains(q) ||
        tip.contains(q);
  }

  List<AccessAreaDef> _visibleChildren(AccessAreaDef parent) {
    return AccessAreaCatalog.childrenOf(parent.id).where(_matches).toList();
  }

  Future<void> _persist(String message) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final json = _doc.toJson();
      await SupabaseService.updateProfileAccess(widget.employee.id, json);
      widget.onSettings(json);
      if (!mounted) return;
      setState(() => _status = message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Kunne ikke lagre: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(AccessAreaDef area, bool on) async {
    if (_lockedArea(area)) return;
    if (on) {
      _doc.set(area.id, AccessAction.view, true);
      _doc.ensureParentViews(area.id);
    } else {
      _doc.setAreaAll(area.id, false);
    }
    await _persist(on ? '${area.title} er på' : '${area.title} er av');
  }

  Future<void> _addLink() async {
    final area = _linkChoices.cast<AccessAreaDef?>().firstWhere(
          (a) => a!.id == _linkAreaId,
          orElse: () => null,
        );
    final title = _title.text.trim();
    if (area == null || title.isEmpty || area.routePath == null) return;
    _doc.liveLinks.add({
      'id': '${area.id}-${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'path': area.routePath!,
    });
    _doc.set(area.id, AccessAction.view, true);
    _doc.ensureParentViews(area.id);
    _title.clear();
    await _persist('«$title» vises i Mer');
  }

  Future<void> _removeLink(Map<String, String> link) async {
    _doc.liveLinks.removeWhere((l) => l['id'] == link['id']);
    await _persist('«${link['title']}» er fjernet');
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.employee.role == UserRole.superadmin;
    final pages = AccessAreaCatalog.areas.where((a) => a.id != 'more').toList();
    final onCount = pages.where(_on).length;
    final offCount = pages.length - onCount;

    final roots = AccessAreaCatalog.roots.where((r) {
      if (_matches(r)) return true;
      return AccessAreaCatalog.descendants(r.id).any((id) {
        final child = AccessAreaCatalog.byId[id];
        return child != null && _matches(child);
      });
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text(
          'Tilgang · ${widget.employee.fullName}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A2E24),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$onCount på · $offCount av. Lagres med en gang. Minste tilgang gjelder.',
          style: const TextStyle(color: Color(0xFF3D4F45), fontSize: 13),
        ),
        if (locked) ...[
          const SizedBox(height: 8),
          const Text(
            'Superadmin ser alltid alt. Bytt rolle for å skjule sider.',
            style: TextStyle(
              color: Color(0xFF9A5B00),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 6),
          Text(
            _status!,
            style: const TextStyle(
              color: Color(0xFF1B5E20),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          style: const TextStyle(color: Color(0xFF1A2E24)),
          decoration: InputDecoration(
            hintText: 'Søk side, for eksempel ferie, kamera, GDPR…',
            hintStyle: const TextStyle(color: Color(0xFF6B7A70)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF1A2E24)),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in ['Alle', 'På', 'Av', ..._groups.keys])
              ChoiceChip(
                label: Text(name),
                selected: _filter == name,
                onSelected: (_) => setState(() => _filter = name),
                visualDensity: VisualDensity.compact,
                selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.22),
                labelStyle: TextStyle(
                  color: const Color(0xFF1A2E24),
                  fontWeight: _filter == name ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (roots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Ingen sider matcher søket.',
              style: TextStyle(color: Color(0xFF3D4F45)),
            ),
          ),
        for (final root in roots) _groupCard(root, locked),
        const SizedBox(height: 8),
        _shortcutCard(locked),
      ],
    );
  }

  Widget _groupCard(AccessAreaDef root, bool locked) {
    final kids = AccessAreaCatalog.childrenOf(root.id);
    final shownKids = _query.isEmpty && _filter != 'På' && _filter != 'Av'
        ? kids
        : _visibleChildren(root);
    final tree = [root, ...AccessAreaCatalog.descendants(root.id)
        .map((id) => AccessAreaCatalog.byId[id])
        .whereType<AccessAreaDef>()
        .where((a) => a.id != 'more')];
    final onN = tree.where((a) => a.id == 'more' || _on(a)).length;
    final open = _open.contains(root.id) || _query.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE3EBE6)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              root.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2E24),
              ),
            ),
            subtitle: Text(
              '$onN/${tree.length} på · ${_tips[root.id] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF3D4F45), fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _switch(root, locked),
                if (kids.isNotEmpty)
                  Icon(open ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: kids.isEmpty
                ? null
                : () => setState(() {
                      if (open) {
                        _open.remove(root.id);
                      } else {
                        _open.add(root.id);
                      }
                    }),
          ),
          if (open && kids.isNotEmpty) ...[
            for (final child in shownKids) ...[
              _row(child, locked, indent: 1),
              for (final grand in _visibleChildren(child))
                _row(grand, locked, indent: 2),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(AccessAreaDef area, bool locked, {required int indent}) {
    final parentOff = area.parentId != null &&
        !_doc.get(area.parentId!, AccessAction.view) &&
        area.parentId != 'more';
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + indent * 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: parentOff
                          ? const Color(0xFF8A978F)
                          : const Color(0xFF1A2E24),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    parentOff
                        ? 'Av fordi ${_parentTitle(area.parentId!)} er av.'
                        : (_tips[area.id] ?? 'Styrer om denne funksjonen vises.'),
                    style: const TextStyle(
                      color: Color(0xFF5C6B63),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _switch(area, locked || parentOff),
        ],
      ),
    );
  }

  Widget _switch(AccessAreaDef area, bool locked) {
    if (_lockedArea(area)) {
      return const Padding(
        padding: EdgeInsets.only(right: 12),
        child: Text(
          'Alltid',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1B5E20),
          ),
        ),
      );
    }
    return Switch(
      value: _on(area),
      onChanged: locked || _busy ? null : (v) => _toggle(area, v),
    );
  }

  Widget _shortcutCard(bool locked) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE3EBE6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Snarvei i Mer',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2E24),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Viser en side som allerede finnes, med eget navn. Ingen ny bygg.',
              style: TextStyle(color: Color(0xFF5C6B63), fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              style: const TextStyle(color: Color(0xFF1A2E24)),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Navn i menyen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _linkAreaId,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Side',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final a in _linkChoices)
                  DropdownMenuItem(value: a.id, child: Text(a.title)),
              ],
              onChanged: locked ? null : (v) => setState(() => _linkAreaId = v),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: locked || _busy ? null : _addLink,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Legg til'),
              ),
            ),
            for (final link in _doc.liveLinks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(link['title'] ?? ''),
                subtitle: Text(link['path'] ?? ''),
                trailing: IconButton(
                  tooltip: 'Fjern',
                  onPressed: _busy ? null : () => _removeLink(link),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _parentTitle(String id) => AccessAreaCatalog.byId[id]?.title ?? id;
}
