import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner_route_dispatch_history.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'widgets/partner_route_partner_status.dart';
import 'widgets/partner_ui.dart';

/// MAVI: oversikt over når ruter ble sendt, av hvem, og når PDF ble lest.
class PartnerRouteDispatchHistoryScreen extends StatefulWidget {
  const PartnerRouteDispatchHistoryScreen({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<PartnerRouteDispatchHistoryScreen> createState() =>
      _PartnerRouteDispatchHistoryScreenState();
}

enum _HistoryFilter { all, sent, pdfRead, pdfUnread, staged }

class _PartnerRouteDispatchHistoryScreenState
    extends State<PartnerRouteDispatchHistoryScreen> {
  late DateTime _day;
  bool _loading = true;
  String? _error;
  List<PartnerRouteDispatchHistoryRow> _rows = const [];
  _HistoryFilter _filter = _HistoryFilter.all;
  final _search = TextEditingController();

  static final _dayFmt = DateFormat('EEEE d. MMMM yyyy', 'nb_NO');
  static final _timeFmt = DateFormat('dd.MM.yyyy HH:mm', 'nb_NO');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = widget.initialDate ?? now;
    _day = DateTime(seed.year, seed.month, seed.day);
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        if (mounted) {
          setState(() {
            _rows = const [];
            _loading = false;
            _error = 'Ingen bedrift valgt';
          });
        }
        return;
      }
      final rows = await PartnerService.fetchRouteDispatchHistory(
        companyId: cid,
        fromDate: _day,
        toDate: _day,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Velg rutedato',
      cancelText: 'Avbryt',
      confirmText: 'Velg',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = DateTime(picked.year, picked.month, picked.day);
    });
    await _load();
  }

  void _shiftDay(int delta) {
    setState(() {
      _day = _day.add(Duration(days: delta));
    });
    _load();
  }

  List<PartnerRouteDispatchHistoryRow> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      switch (_filter) {
        case _HistoryFilter.all:
          break;
        case _HistoryFilter.sent:
          if (r.dispatchStatus != 'sent' && r.dispatchStatus != 'registered') {
            return false;
          }
          break;
        case _HistoryFilter.pdfRead:
          if (!r.pdfWasOpened) return false;
          break;
        case _HistoryFilter.pdfUnread:
          if (r.pdfWasOpened || r.dispatchStatus == 'staged') return false;
          break;
        case _HistoryFilter.staged:
          if (r.dispatchStatus != 'staged') return false;
          break;
      }
      if (q.isEmpty) return true;
      final hay = [
        r.maviLabel,
        r.partnerName,
        r.title,
        r.sentByName,
        r.pdfOpenedByName,
        r.ackByName,
        r.shiftName,
        r.registrationNumber,
      ].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _rows.where((r) => r.dispatchStatus == 'sent').length;
    final registered =
        _rows.where((r) => r.dispatchStatus == 'registered').length;
    final read = _rows.where((r) => r.pdfWasOpened).length;
    final unread = _rows
        .where(
          (r) =>
              !r.pdfWasOpened &&
              (r.dispatchStatus == 'sent' || r.dispatchStatus == 'registered'),
        )
        .length;
    final staged = _rows.where((r) => r.dispatchStatus == 'staged').length;
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rutehistorikk'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: PartnerUi.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Forrige dag',
                          onPressed: _loading ? null : () => _shiftDay(-1),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: _loading ? null : _pickDate,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Rutedato',
                                    style: DriftProTheme.labelSm.copyWith(
                                      color: PartnerUi.mutedText(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dayFmt.format(_day),
                                    textAlign: TextAlign.center,
                                    style: DriftProTheme.labelLg.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Neste dag',
                          onPressed: _loading ? null : () => _shiftDay(1),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                        IconButton(
                          tooltip: 'Velg dato',
                          onPressed: _loading ? null : _pickDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(
                      label: 'Sendt',
                      value: '$sent',
                      color: DriftProTheme.primaryGreen,
                      selected: _filter == _HistoryFilter.sent,
                      onTap: () => setState(() {
                        _filter = _filter == _HistoryFilter.sent
                            ? _HistoryFilter.all
                            : _HistoryFilter.sent;
                      }),
                    ),
                    _StatChip(
                      label: 'Uten varsel',
                      value: '$registered',
                      color: Colors.blueGrey,
                      selected: false,
                      onTap: null,
                    ),
                    _StatChip(
                      label: 'PDF lest',
                      value: '$read',
                      color: Colors.teal,
                      selected: _filter == _HistoryFilter.pdfRead,
                      onTap: () => setState(() {
                        _filter = _filter == _HistoryFilter.pdfRead
                            ? _HistoryFilter.all
                            : _HistoryFilter.pdfRead;
                      }),
                    ),
                    _StatChip(
                      label: 'Ikke lest',
                      value: '$unread',
                      color: Colors.orange.shade800,
                      selected: _filter == _HistoryFilter.pdfUnread,
                      onTap: () => setState(() {
                        _filter = _filter == _HistoryFilter.pdfUnread
                            ? _HistoryFilter.all
                            : _HistoryFilter.pdfUnread;
                      }),
                    ),
                    if (staged > 0)
                      _StatChip(
                        label: 'Kladd',
                        value: '$staged',
                        color: Colors.grey.shade700,
                        selected: _filter == _HistoryFilter.staged,
                        onTap: () => setState(() {
                          _filter = _filter == _HistoryFilter.staged
                              ? _HistoryFilter.all
                              : _HistoryFilter.staged;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Søk MAVI, partner, avsender…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _search.clear(),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const DriftProLoadingCenter()
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      )
                    : visible.isEmpty
                        ? Center(
                            child: Text(
                              _rows.isEmpty
                                  ? 'Ingen ruter denne dagen'
                                  : 'Ingen treff med valgt filter',
                              style: TextStyle(
                                color: PartnerUi.mutedText(context),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: DriftProTheme.primaryGreen,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) =>
                                  _HistoryCard(row: visible[i], timeFmt: _timeFmt),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color.withValues(alpha: 0.18) : PartnerUi.surface(context);
    final border = selected ? color : color.withValues(alpha: 0.35);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PartnerUi.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.row, required this.timeFmt});

  final PartnerRouteDispatchHistoryRow row;
  final DateFormat timeFmt;

  String _fmt(DateTime? t) => t == null ? '—' : timeFmt.format(t.toLocal());

  String get _statusLabel {
    switch (row.dispatchStatus) {
      case 'sent':
        return 'Varslet';
      case 'registered':
        return 'Uten varsel';
      case 'staged':
        return 'Kladd';
      default:
        return row.dispatchStatus;
    }
  }

  Color get _statusColor {
    switch (row.dispatchStatus) {
      case 'sent':
        return DriftProTheme.primaryGreen;
      case 'registered':
        return Colors.blueGrey;
      case 'staged':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);

    return Material(
      color: PartnerUi.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    row.maviLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.partnerName ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: DriftProTheme.labelLg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if ((row.shiftName ?? '').isNotEmpty ||
                (row.title ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if ((row.shiftName ?? '').isNotEmpty) row.shiftName!,
                  if ((row.title ?? '').isNotEmpty) row.title!,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
            const SizedBox(height: 12),
            _InfoLine(
              icon: Icons.send_outlined,
              label: 'Sendt',
              value: row.sentAt == null && row.dispatchStatus == 'staged'
                  ? 'Ikke sendt ennå'
                  : '${_fmt(row.sentAt)} · ${row.sentByName?.trim().isNotEmpty == true ? row.sentByName! : 'Ukjent'}',
            ),
            const SizedBox(height: 10),
            PartnerRoutePartnerStatus.fromHistory(row: row),
            if (row.dispatchStatus == 'sent' && row.notifyChannels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Kanaler: ${row.notifyChannels.map((c) => c.toUpperCase()).join(' · ')}',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? PartnerUi.mutedText(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, height: 1.25),
          ),
        ),
      ],
    );
  }
}
