import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/supabase_service.dart';
import '../../core/services/ticket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import '../../widgets/resolved_storage_image.dart';

class TicketDetailScreen extends StatefulWidget {
  final Ticket ticket;
  /// Settes når leder/admin åpner fra kontrollsenter (valgfritt — lastes ellers).
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
  List<UserProfile> _profiles = const [];
  bool _loading = true;
  final _commentController = TextEditingController();
  final _rootCauseController = TextEditingController();
  final _resolutionController = TextEditingController();
  final _internalController = TextEditingController();
  bool _savingMeta = false;
  bool _savingComment = false;
  String? _assigneeId;
  DateTime? _dueDate;

  bool get _coord {
    final p = widget.coordinatorProfile ?? _me;
    return p?.canCoordinateTickets ?? false;
  }

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _assigneeId = _ticket.assignedTo;
    _dueDate = _ticket.dueDate;
    _rootCauseController.text = _ticket.rootCause ?? '';
    _resolutionController.text = _ticket.resolutionComment ?? '';
    _internalController.text = _ticket.internalNotes ?? '';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _initialLoad();
  }

  Future<void> _refreshTicket() async {
    try {
      final fresh = await SupabaseService.fetchTicketById(_ticket.id);
      final profile = widget.coordinatorProfile ??
          await SupabaseService.fetchCurrentUserProfile();
      if (fresh != null) {
        _ticket = fresh;
        _assigneeId = fresh.assignedTo;
        _dueDate = fresh.dueDate;
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
      if (mounted && _coord) await _loadProfiles();
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

  Future<void> _loadProfiles() async {
    if (!_coord) return;
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final list = await SupabaseService.fetchProfiles(companyId: cid);
      if (mounted) setState(() => _profiles = list);
    } catch (e) {
      debugPrint('profiles: $e');
    }
  }

  Future<void> _stamp(TicketStatus next) async {
    if (!_coord) return;
    setState(() => _savingComment = true);
    try {
      await SupabaseService.addTicketComment(
        ticketId: _ticket.id,
        comment: 'Status satt til «${next.label}».',
        newStatus: next,
      );
      await _refreshTicket();
      await _loadComments();
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

  Future<void> _saveCoordinatorFields() async {
    if (!_coord) return;
    setState(() => _savingMeta = true);
    try {
      await SupabaseService.updateTicket(_ticket.id, {
        'assigned_to': _assigneeId,
        'due_date': _dueDate?.toIso8601String().split('T').first,
        'root_cause': _rootCauseController.text.trim().isEmpty
            ? null
            : _rootCauseController.text.trim(),
        'resolution_comment': _resolutionController.text.trim().isEmpty
            ? null
            : _resolutionController.text.trim(),
        'internal_notes': _internalController.text.trim().isEmpty
            ? null
            : _internalController.text.trim(),
      });
      await _refreshTicket();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret')),
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

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dueDate ?? DateTime.now(),
    );
    if (d != null) setState(() => _dueDate = d);
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
        title: Text(
          _ticket.ticketNumber != null
              ? 'Avvik #${_ticket.ticketNumber}'
              : 'Avvik',
        ),
        actions: [
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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHero(isDark),
                      if (_coord) ...[
                        const SizedBox(height: 16),
                        _buildStampBar(isDark),
                        const SizedBox(height: 16),
                        _buildCoordinatorCard(isDark),
                      ],
                      const SizedBox(height: 20),
                      _buildDescription(isDark),
                      if (_ticket.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildImages(isDark),
                      ],
                      const Divider(height: 40),
                      Text(
                        'Historikk',
                        style: DriftProTheme.headingMd,
                      ),
                      const SizedBox(height: 12),
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
          Text(_ticket.title, style: DriftProTheme.headingMd),
          const SizedBox(height: 8),
          Text(
            _ticket.isAnonymous
                ? 'Innrapportert anonymt'
                : 'Rapportert av: ${_ticket.reporterName ?? "Ukjent"}',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
          ),
          if (_ticket.assigneeName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Ansvarlig: ${_ticket.assigneeName}',
              style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
            ),
          ],
          if (_ticket.dueDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Frist: ${DateFormat("dd.MM.yyyy").format(_ticket.dueDate!)}',
              style: DriftProTheme.bodySm.copyWith(
                color: _ticket.isOpen &&
                        _ticket.dueDate!.isBefore(DateTime.now())
                    ? Colors.redAccent
                    : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStampBar(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hurtigstempler', style: DriftProTheme.labelLg),
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

  Widget _buildCoordinatorCard(bool isDark) {
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
          Text('Saksbehandling', style: DriftProTheme.headingSm),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _assigneeId,
            decoration: const InputDecoration(
              labelText: 'Tildel ansvarlig',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Ikke tildelt'),
              ),
              ..._profiles.map(
                (p) => DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(p.fullName),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _assigneeId = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _dueDate == null
                        ? 'Sett frist'
                        : DateFormat('dd.MM.yyyy').format(_dueDate!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _dueDate = null),
                child: const Text('Fjern frist'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rootCauseController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Årsak / analyse',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _resolutionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Avsluttende vurdering / oppfølging',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _internalController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Internt notat (kun koordinatorer)',
              border: OutlineInputBorder(),
            ),
          ),
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
                  : const Text('Lagre saksfelt'),
            ),
          ),
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
                    Text(
                      comment.userName ?? 'Ukjent',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (comment.createdAt != null)
                      Text(
                        DateFormat('dd.MM HH:mm').format(comment.createdAt!),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                  ],
                ),
                if (comment.isStatusChange &&
                    comment.oldStatus != null &&
                    comment.newStatus != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${comment.oldStatus!.label} → ${comment.newStatus!.label}',
                    style: TextStyle(
                      fontSize: 11,
                      color: DriftProTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
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
                  hintText: 'Kommentar til saken…',
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
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
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
