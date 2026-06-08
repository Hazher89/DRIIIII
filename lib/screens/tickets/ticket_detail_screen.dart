import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/case_trace/case_trace_chip.dart';
import '../../core/services/hms/hms_pdf_generators.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/ticket_service.dart';
import '../hms/widgets/hms_pdf_export_button.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import '../../widgets/resolved_storage_image.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class TicketDetailScreen extends StatefulWidget {
  final Ticket ticket;
  final UserProfile? coordinatorProfile;

  const TicketDetailScreen({
    super.key,
    required this.ticket,
    this.coordinatorProfile,
  });

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  late Ticket _ticket;
  UserProfile? _me;
  List<TicketComment> _comments = [];
  bool _loading = true;
  final _commentController = TextEditingController();
  final _rootCauseController = TextEditingController();
  final _resolutionController = TextEditingController();
  final _internalController = TextEditingController();
  bool _savingMeta = false;
  bool _savingComment = false;

  static final _stampFmt = DateFormat('dd.MM.yyyy HH:mm');

  bool get _coord {
    final p = widget.coordinatorProfile ?? _me;
    return p?.canCoordinateTickets ?? false;
  }

  bool get _isReporter =>
      _me != null && _me!.id == _ticket.reportedBy;

  bool get _isAssignee =>
      _me != null &&
      _ticket.assignedTo != null &&
      _me!.id == _ticket.assignedTo;

  bool get _canProcess => _coord || _isAssignee;

  bool get _isClosed =>
      _ticket.status == TicketStatus.lukket ||
      _ticket.status == TicketStatus.tiltakUtfort;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _rootCauseController.text = _ticket.rootCause ?? '';
    _resolutionController.text = _ticket.resolutionComment ?? '';
    _internalController.text = _ticket.internalNotes ?? '';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _initialLoad();
  }

  Future<void> _deleteTicket() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett avvik til arkiv'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_ticket.displayTraceRef} flyttes til slettet-arkiv. '
              'Sporings-ID kan brukes for oppslag senere.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Kommentar (påkrevd)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      final updated = await SupabaseService.softDeleteTicket(
        ticketId: _ticket.id,
        deletionComment: ctrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _ticket = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_ticket.displayTraceRef} arkivert')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _refreshTicket() async {
    try {
      final fresh = await SupabaseService.fetchTicketById(_ticket.id);
      final profile = widget.coordinatorProfile ??
          await SupabaseService.fetchCurrentUserProfile();
      if (fresh != null) {
        _ticket = fresh;
        _rootCauseController.text = fresh.rootCause ?? '';
        _resolutionController.text = fresh.resolutionComment ?? '';
        _internalController.text = fresh.internalNotes ?? '';
      }
      _me = profile;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('refresh ticket: $e');
    }
  }

  Future<void> _initialLoad() async {
    setState(() => _loading = true);
    try {
      await _refreshTicket();
      await _loadComments();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadComments() async {
    try {
      final c = await SupabaseService.fetchTicketComments(_ticket.id);
      if (mounted) setState(() => _comments = c);
    } catch (e) {
      debugPrint('comments: $e');
    }
  }

  String _stampLine(String action) {
    final name = _me?.fullName ?? 'Bruker';
    return '$action · $name · ${_stampFmt.format(DateTime.now())}';
  }

  Future<void> _stamp(TicketStatus next) async {
    if (!_canProcess) return;

    if ((next == TicketStatus.lukket || next == TicketStatus.tiltakUtfort) &&
        _resolutionController.text.trim().isEmpty) {
      final ok = await _promptResolution(required: true);
      if (!ok) return;
    }

    setState(() => _savingComment = true);
    try {
      await SupabaseService.addTicketComment(
        ticketId: _ticket.id,
        comment: _stampLine('Status satt til «${next.label}»'),
        newStatus: next,
        resolutionComment: _resolutionController.text.trim(),
        rootCause: _rootCauseController.text.trim(),
      );
      await _refreshTicket();
      await _loadComments();
      if (mounted && _isClosed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saken er behandlet. Avsender får SMS med oppsummering.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke oppdatere: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingComment = false);
    }
  }

  Future<bool> _promptResolution({required bool required}) async {
    final ctrl = TextEditingController(text: _resolutionController.text);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avsluttende vurdering'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: required
                ? 'Beskriv hvordan saken er behandlet (påkrevd)'
                : 'Valgfritt notat til avsender',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () {
              if (required && ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    if (result == true) {
      _resolutionController.text = ctrl.text.trim();
      return true;
    }
    return false;
  }

  Future<void> _saveCoordinatorFields() async {
    if (!_canProcess) return;
    setState(() => _savingMeta = true);
    try {
      await SupabaseService.updateTicket(_ticket.id, {
        'root_cause': _rootCauseController.text.trim().isEmpty
            ? null
            : _rootCauseController.text.trim(),
        'resolution_comment': _resolutionController.text.trim().isEmpty
            ? null
            : _resolutionController.text.trim(),
        if (_coord)
          'internal_notes': _internalController.text.trim().isEmpty
              ? null
              : _internalController.text.trim(),
      });
      await SupabaseService.addTicketComment(
        ticketId: _ticket.id,
        comment: _stampLine('Saksfelt oppdatert'),
      );
      await _refreshTicket();
      await _loadComments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret med tidsstempel')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMeta = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingComment = true);
    try {
      await SupabaseService.addTicketComment(
        ticketId: _ticket.id,
        comment: text,
      );
      _commentController.clear();
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingComment = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _rootCauseController.dispose();
    _resolutionController.dispose();
    _internalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: Text(_ticket.displayTraceRef),
        actions: [
          HmsPdfExportButton(
            fileName: _ticket.ticketNumber != null
                ? 'avvik_${_ticket.ticketNumber}'
                : 'avvik_${_ticket.id.substring(0, 8)}',
            onGenerate: () => HmsPdfGenerators.ticket(
              _ticket,
              comments: _comments,
              includeInternalNotes: _coord,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _refreshTicket();
              await _loadComments();
            },
          ),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHero(isDark),
                      if (_isClosed) ...[
                        const SizedBox(height: 16),
                        _buildOutcomeCard(isDark),
                      ],
                      if (_canProcess && !_isClosed) ...[
                        const SizedBox(height: 16),
                        _buildStampBar(isDark),
                        const SizedBox(height: 16),
                        _buildProcessingCard(isDark),
                      ],
                      if (_canProcess && _isClosed) ...[
                        const SizedBox(height: 16),
                        _buildProcessingCard(isDark, readOnly: true),
                      ],
                      if (_me?.isAdmin == true && !_ticket.isDeleted) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _deleteTicket,
                          icon: const Icon(Icons.archive_outlined),
                          label: const Text('Slett til arkiv (beholder sporings-ID)'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildDescription(isDark),
                      if (_ticket.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildImages(isDark),
                      ],
                      const Divider(height: 40),
                      Row(
                        children: [
                          Text('Historikk', style: DriftProTheme.headingMd),
                          const Spacer(),
                          Text(
                            '${_comments.length} hendelse(r)',
                            style: DriftProTheme.bodySm.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_comments.isEmpty)
                        Text(
                          'Ingen hendelser ennå.',
                          style: DriftProTheme.bodySm.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ..._comments.map((c) => _buildCommentTile(c, isDark)),
                    ],
                  ),
                ),
                _buildCommentBar(isDark),
              ],
            ),
    );
  }

  Widget _buildHero(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniBadge(_ticket.status.label, _statusColor(_ticket.status)),
              _miniBadge(_ticket.severity.label, _sevColor(_ticket.severity)),
              if (_ticket.departmentName != null)
                _miniBadge(_ticket.departmentName!, Colors.indigo),
            ],
          ),
          const SizedBox(height: 12),
          CaseTraceChip(traceRef: _ticket.displayTraceRef, id: _ticket.id),
          if (_ticket.isDeleted) ...[
            const SizedBox(height: 8),
            Text(
              'Slettet — sporings-ID ${_ticket.displayTraceRef} beholdes for revisjon.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
            if (_ticket.deletionComment?.isNotEmpty == true)
              Text(
                '«${_ticket.deletionComment}»',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
          const SizedBox(height: 12),
          Text(_ticket.title, style: DriftProTheme.headingMd),
          const SizedBox(height: 8),
          Text(
            _ticket.isAnonymous
                ? 'Innrapportert anonymt'
                : 'Rapportert av: ${_ticket.reporterName ?? "Ukjent"}',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
          ),
          if (_ticket.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Mottatt: ${_stampFmt.format(_ticket.createdAt!.toLocal())}',
              style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
            ),
          ],
          if (_ticket.assigneeName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Saksbehandler: ${_ticket.assigneeName}',
              style: DriftProTheme.bodySm.copyWith(
                color: DriftProTheme.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_isReporter && !_isClosed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.sms_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Du får SMS når saken settes under arbeid og når den er ferdig behandlet.',
                      style: DriftProTheme.bodySm.copyWith(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutcomeCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  color: DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              Text('Behandlet sak', style: DriftProTheme.headingSm),
            ],
          ),
          const SizedBox(height: 12),
          _outcomeRow('Status', _ticket.status.label),
          if (_ticket.resolvedByName != null)
            _outcomeRow('Behandlet av', _ticket.resolvedByName!),
          if (_ticket.resolvedAt != null)
            _outcomeRow(
              'Tidsstempel',
              _stampFmt.format(_ticket.resolvedAt!.toLocal()),
            ),
          if (_ticket.rootCause != null && _ticket.rootCause!.isNotEmpty)
            _outcomeRow('Årsak / analyse', _ticket.rootCause!),
          if (_ticket.resolutionComment != null &&
              _ticket.resolutionComment!.isNotEmpty)
            _outcomeRow('Lederens vurdering', _ticket.resolutionComment!),
        ],
      ),
    );
  }

  Widget _outcomeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: DriftProTheme.bodyMd),
        ],
      ),
    );
  }

  Widget _buildStampBar(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stempler (navn + dato/tid)', style: DriftProTheme.labelLg),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TicketStatus.values.map((s) {
            final active = _ticket.status == s;
            return FilledButton.tonal(
              onPressed: _savingComment || active ? null : () => _stamp(s),
              style: FilledButton.styleFrom(
                backgroundColor: active
                    ? DriftProTheme.primaryGreen.withValues(alpha: 0.2)
                    : null,
              ),
              child: Text(s.label, style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildProcessingCard(bool isDark, {bool readOnly = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            readOnly ? 'Behandlingsdokumentasjon' : 'Behandle avvik',
            style: DriftProTheme.headingSm,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rootCauseController,
            readOnly: readOnly,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Årsak / analyse',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _resolutionController,
            readOnly: readOnly,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Vurdering til avsender *',
              helperText: 'Vises for den som meldte inn + sendes i SMS ved lukking',
              border: OutlineInputBorder(),
            ),
          ),
          if (_coord) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _internalController,
              readOnly: readOnly,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Internt notat (kun koordinatorer)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (!readOnly) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _savingMeta ? null : _saveCoordinatorFields,
                child: _savingMeta
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Lagre med tidsstempel'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDescription(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Beskrivelse', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        Text(_ticket.description, style: DriftProTheme.bodyMd),
      ],
    );
  }

  Widget _buildImages(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dokumentasjon', style: DriftProTheme.labelLg),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _ticket.imageUrls.length,
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                margin: const EdgeInsets.only(right: 12),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200,
                ),
                child: ResolvedStorageImage(
                  storageRef: _ticket.imageUrls[index],
                  width: 120,
                  height: 120,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _miniBadge(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCommentTile(TicketComment comment, bool isDark) {
    final ts = comment.createdAt != null
        ? _stampFmt.format(comment.createdAt!.toLocal())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            child: Text(
              (comment.userName ?? '?').isNotEmpty
                  ? (comment.userName![0]).toUpperCase()
                  : '?',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.userName ?? 'Ukjent',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (ts.isNotEmpty)
                      Text(
                        ts,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                if (comment.isStatusChange &&
                    comment.oldStatus != null &&
                    comment.newStatus != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${comment.oldStatus!.label} → ${comment.newStatus!.label}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: DriftProTheme.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? DriftProTheme.cardDark : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(comment.comment),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                decoration: InputDecoration(
                  hintText: _canProcess
                      ? 'Kommentar til saken…'
                      : 'Skriv til saksbehandler…',
                  filled: true,
                  fillColor: isDark ? DriftProTheme.cardDark : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              onPressed: _savingComment ? null : _submitComment,
              backgroundColor: DriftProTheme.primaryGreen,
              child: _savingComment
                  ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
                  : const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(TicketStatus status) {
    switch (status) {
      case TicketStatus.aapen:
        return Colors.orange;
      case TicketStatus.underBehandling:
        return Colors.blue;
      case TicketStatus.tiltakUtfort:
        return Colors.teal;
      case TicketStatus.lukket:
        return Colors.grey;
    }
  }

  Color _sevColor(TicketSeverity s) {
    switch (s) {
      case TicketSeverity.lav:
        return Colors.green;
      case TicketSeverity.middels:
        return Colors.orange;
      case TicketSeverity.hoy:
        return Colors.red;
      case TicketSeverity.kritisk:
        return Colors.purple;
    }
  }
}
