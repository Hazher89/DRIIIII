import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/email/email_log_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/email_log_filters.dart';
import '../../models/partner/sap_route_inbox.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../profile/widgets/email_outbox_log_panel.dart';

/// Mer → E-post: utgående varsler + innkommende SAP/Office 365.
class MailHubScreen extends StatefulWidget {
  const MailHubScreen({super.key, this.initialTab});

  /// `utgaende` | `innkommende`
  final String? initialTab;

  @override
  State<MailHubScreen> createState() => _MailHubScreenState();
}

class _MailHubScreenState extends State<MailHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _outSent = 0;
  int _outQueued = 0;
  int _outFailed = 0;
  int _inPending = 0;
  int _inTotal = 0;
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    final start = widget.initialTab == 'innkommende' ? 1 : 0;
    _tabs = TabController(length: 2, vsync: this, initialIndex: start);
    _loadStats();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      final results = await Future.wait([
        EmailLogService.countLog(
          filters: const EmailLogFilters(status: 'sendt'),
        ),
        EmailLogService.countLog(
          filters: const EmailLogFilters(status: 'i_ko'),
        ),
        EmailLogService.countLog(
          filters: const EmailLogFilters(status: 'feilet'),
        ),
        if (cid != null)
          PartnerService.fetchSapRouteInboxRecent(cid, limit: 200)
        else
          Future.value(const <SapRouteInboxItem>[]),
      ]);
      final inbound = results[3] as List<SapRouteInboxItem>;
      if (!mounted) return;
      setState(() {
        _outSent = results[0] as int;
        _outQueued = results[1] as int;
        _outFailed = results[2] as int;
        _inTotal = inbound.length;
        _inPending = inbound.where((e) => e.status == 'pending').length;
        _statsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        title: const Text('E-post'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Oppdater tall',
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: DriftProTheme.primaryGreen,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: DriftProTheme.primaryGreen,
          tabs: const [
            Tab(icon: Icon(Icons.outbox_outlined), text: 'Utgående'),
            Tab(icon: Icon(Icons.inbox_outlined), text: 'Innkommende'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildHeroStats(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                EmailOutboxLogPanel(),
                _SapInboundMailPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStats() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3D28), Color(0xFF217346)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3D28).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Office 365 · DriftPro',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'E-postkontroll',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Utgående via Graph (driftpro@mavilogistikk.no) · '
            'Innkommende SAP Backup Form',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (_statsLoading)
            const LinearProgressIndicator(
              color: Colors.white,
              backgroundColor: Colors.white24,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statChip('Sendt', '$_outSent', Icons.check_circle_outline),
                _statChip('I kø', '$_outQueued', Icons.schedule),
                _statChip('Feilet', '$_outFailed', Icons.error_outline),
                _statChip('SAP inn', '$_inTotal', Icons.mark_email_read_outlined),
                _statChip('SAP venter', '$_inPending', Icons.hourglass_top),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SapInboundMailPanel extends StatefulWidget {
  const _SapInboundMailPanel();

  @override
  State<_SapInboundMailPanel> createState() => _SapInboundMailPanelState();
}

class _SapInboundMailPanelState extends State<_SapInboundMailPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final List<SapRouteInboxItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
          !_loading &&
          !_loadingMore &&
          _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift');
      final rows = await PartnerService.fetchSapRouteInboxRecent(
        cid,
        limit: 40,
        offset: 0,
        status: _statusFilter,
      );
      final q = _search.text.trim().toLowerCase();
      final filtered = q.isEmpty
          ? rows
          : rows.where((r) {
              return r.fileName.toLowerCase().contains(q) ||
                  (r.subject ?? '').toLowerCase().contains(q) ||
                  (r.senderEmail ?? '').toLowerCase().contains(q) ||
                  (r.detectedMaviCode ?? '').toLowerCase().contains(q);
            }).toList();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(filtered);
        _hasMore = rows.length >= 40;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Innkommende e-post: $e')),
      );
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final rows = await PartnerService.fetchSapRouteInboxRecent(
        cid,
        limit: 40,
        offset: _items.length,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length >= 40;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _statusLabel(String s) => switch (s) {
        'pending' => 'Venter',
        'imported' => 'Importert',
        'rejected' => 'Avvist / manuell',
        _ => s,
      };

  Color _statusColor(String s) => switch (s) {
        'pending' => Colors.orange.shade800,
        'imported' => Colors.green.shade800,
        'rejected' => Colors.deepOrange.shade800,
        _ => Colors.blueGrey.shade700,
      };

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Søk avsender, emne, fil, MAVI…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onSubmitted: (_) => _load(refresh: true),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in [
                    (null, 'Alle'),
                    ('pending', 'Venter'),
                    ('imported', 'Importert'),
                    ('rejected', 'Manuell'),
                  ])
                    FilterChip(
                      label: Text(e.$2),
                      selected: _statusFilter == e.$1,
                      onSelected: (_) {
                        setState(() => _statusFilter = e.$1);
                        _load(refresh: true);
                      },
                    ),
                  IconButton(
                    tooltip: 'Oppdater',
                    onPressed: () => _load(refresh: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const DriftProLoadingCenter()
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        'Ingen innkommende SAP-mail ennå.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(refresh: true),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: DriftProLoadingIndicator()),
                            );
                          }
                          final item = _items[i];
                          final color = _statusColor(item.status);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: color.withValues(alpha: 0.35),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                14,
                                10,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.mark_email_unread_outlined,
                                  color: color,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                item.subject?.trim().isNotEmpty == true
                                    ? item.subject!
                                    : item.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [
                                        item.senderEmail ?? 'Ukjent avsender',
                                        df.format(item.receivedAt.toLocal()),
                                        if (item.detectedMaviCode != null)
                                          item.detectedMaviCode!,
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade800,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _statusLabel(item.status),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    if ((item.rejectReason ?? '')
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.rejectReason!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
