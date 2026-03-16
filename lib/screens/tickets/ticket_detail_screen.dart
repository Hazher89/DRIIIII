import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import 'package:intl/intl.dart';

class TicketDetailScreen extends StatefulWidget {
  final Ticket ticket;
  const TicketDetailScreen({super.key, required this.ticket});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  late Ticket _ticket;
  List<TicketComment> _comments = [];
  bool _isLoading = true;
  final _commentController = TextEditingController();
  TicketStatus? _selectedNewStatus;
  bool _isSavingComment = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final comments = await SupabaseService.fetchTicketComments(_ticket.id);
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading comments: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty && _selectedNewStatus == null) return;

    setState(() => _isSavingComment = true);
    try {
      final commentText = _commentController.text.trim().isEmpty 
          ? (_selectedNewStatus != null ? 'Status endret til ${_selectedNewStatus!.label}' : '')
          : _commentController.text.trim();

      await SupabaseService.addTicketComment(
        ticketId: _ticket.id,
        comment: commentText,
        newStatus: _selectedNewStatus,
      );

      _commentController.clear();
      
      // Update local ticket status if changed
      if (_selectedNewStatus != null) {
        setState(() {
          _ticket = Ticket(
            id: _ticket.id,
            companyId: _ticket.companyId,
            reportedBy: _ticket.reportedBy,
            title: _ticket.title,
            description: _ticket.description,
            status: _selectedNewStatus!,
            severity: _ticket.severity,
            imageUrls: _ticket.imageUrls,
            assignedTo: _ticket.assignedTo,
          );
          _selectedNewStatus = null;
        });
      }

      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
    } finally {
      setState(() => _isSavingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canManage = SupabaseService.currentUser?.id == _ticket.assignedTo;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: Text('Avvik #${_ticket.id.substring(0, 5)}'),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(isDark),
                    const SizedBox(height: 24),
                    _buildDescription(isDark),
                    const SizedBox(height: 24),
                    if (_ticket.imageUrls.isNotEmpty) _buildImages(isDark),
                    const SizedBox(height: 24),
                    _buildRootCause(isDark),
                    const SizedBox(height: 24),
                    _buildActionPlan(isDark),
                    const Divider(height: 48),
                    Text('Historikk og kommentarer', style: DriftProTheme.headingMd),
                    const SizedBox(height: 16),
                    ..._comments.map((c) => _buildCommentTile(c, isDark)),
                  ],
                ),
              ),
              if (canManage || true) // Allow everyone to comment for now, but focus on assignees for status
                _buildCommentInput(isDark, canManage),
            ],
          ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildBadge(_ticket.status.label, _getStatusColor(_ticket.status)),
              const SizedBox(width: 8),
              _buildBadge(_ticket.severity.label, _getSeverityColor(_ticket.severity)),
            ],
          ),
          const SizedBox(height: 12),
          Text(_ticket.title, style: DriftProTheme.headingMd),
          const SizedBox(height: 8),
          Text(
            'Rapportert av: ${_ticket.reporterName ?? "Anonym"}',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey),
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
        Text('Vedlegg', style: DriftProTheme.labelLg),
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(_ticket.imageUrls[index]),
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRootCause(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.riskLow.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriftProTheme.riskLow.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 20, color: Colors.indigo),
              const SizedBox(width: 8),
              Text('Årsaksanalyse', style: DriftProTheme.labelLg.copyWith(color: Colors.indigo)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_ticket.rootCause ?? 'Ingen årsaksanalyse er utført ennå.', 
            style: DriftProTheme.bodyMd.copyWith(fontStyle: _ticket.rootCause == null ? FontStyle.italic : null)),
        ],
      ),
    );
  }

  Widget _buildActionPlan(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tiltaksplan', style: DriftProTheme.labelLg),
            if (_ticket.assignedTo == SupabaseService.currentUser?.id)
              TextButton.icon(onPressed: () {}, icon: const Icon(Icons.add, size: 16), label: const Text('Nytt tiltak')),
          ],
        ),
        const SizedBox(height: 8),
        if (_ticket.actionPlan.isEmpty)
          const Text('Ingen tiltak er planlagt.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
        else
          ..._ticket.actionPlan.map((action) => _buildActionCard(action, isDark)),
      ],
    );
  }

  Widget _buildActionCard(Map<String, dynamic> action, bool isDark) {
    final isDone = action['status'] == 'done';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(isDone ? Icons.check_circle : Icons.circle_outlined, 
              color: isDone ? Colors.green : Colors.grey, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(action['title'] ?? '', style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null))),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCommentTile(TicketComment comment, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, child: Text(comment.userName?[0] ?? '?')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.userName ?? 'Ukjent', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(
                      comment.createdAt != null ? DateFormat('dd.MM HH:mm').format(comment.createdAt!) : '',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? DriftProTheme.cardDark : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
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

  Widget _buildCommentInput(bool isDark, bool canManage) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : Colors.white,
        border: Border(top: BorderSide(color: isDark ? DriftProTheme.dividerDark : Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage) ...[
              const Text('Endre status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: TicketStatus.values.map((s) => ChoiceChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 10)),
                  selected: _selectedNewStatus == s || (_selectedNewStatus == null && _ticket.status == s),
                  onSelected: (val) => setState(() => _selectedNewStatus = val ? s : null),
                )).toList(),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Legg til en kommentar...',
                      filled: true,
                      fillColor: isDark ? DriftProTheme.cardDark : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.small(
                  onPressed: _isSavingComment ? null : _submitComment,
                  backgroundColor: DriftProTheme.primaryGreen,
                  child: _isSavingComment ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(TicketStatus status) {
    switch (status) {
      case TicketStatus.aapen: return Colors.orange;
      case TicketStatus.underBehandling: return Colors.blue;
      case TicketStatus.tiltakUtfort: return Colors.teal;
      case TicketStatus.lukket: return Colors.grey;
    }
  }

  Color _getSeverityColor(TicketSeverity severity) {
    switch (severity) {
      case TicketSeverity.lav: return Colors.green;
      case TicketSeverity.middels: return Colors.orange;
      case TicketSeverity.hoy: return Colors.red;
      case TicketSeverity.kritisk: return Colors.purple;
    }
  }
}
