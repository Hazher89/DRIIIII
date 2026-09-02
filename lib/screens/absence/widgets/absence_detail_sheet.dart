import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/permissions/user_access.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../new_absence_screen.dart';

/// Detaljvisning for én fraværssøknad — rediger/slett (ventende) eller godkjenn/avvis (leder).
Future<bool?> showAbsenceDetailSheet(
  BuildContext context, {
  required Absence absence,
  required UserProfile profile,
  required int days,
  required Future<void> Function() onChanged,
  Future<void> Function(String id, AbsenceStatus status, {String? decisionComment})?
      onDecide,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AbsenceDetailSheet(
      absence: absence,
      profile: profile,
      days: days,
      onChanged: onChanged,
      onDecide: onDecide,
    ),
  );
}

class _AbsenceDetailSheet extends StatefulWidget {
  const _AbsenceDetailSheet({
    required this.absence,
    required this.profile,
    required this.days,
    required this.onChanged,
    this.onDecide,
  });

  final Absence absence;
  final UserProfile profile;
  final int days;
  final Future<void> Function() onChanged;
  final Future<void> Function(String id, AbsenceStatus status, {String? decisionComment})?
      onDecide;

  @override
  State<_AbsenceDetailSheet> createState() => _AbsenceDetailSheetState();
}

class _AbsenceDetailSheetState extends State<_AbsenceDetailSheet> {
  late Absence _absence;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _absence = widget.absence;
  }

  bool get _isOwner => _absence.userId == widget.profile.id;
  bool get _isPending => _absence.status == AbsenceStatus.ventende;
  bool get _canManage =>
      !_isOwner &&
      (widget.profile.isAdmin ||
          widget.profile.isLeader ||
          widget.profile.access.canApproveLeave);

  Future<void> _edit() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewAbsenceScreen(
          type: _absence.type,
          initialStart: _absence.startDate,
          initialEnd: _absence.endDate,
          existingAbsence: _absence,
        ),
      ),
    );
    if (ok == true && mounted) {
      await widget.onChanged();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett søknad?'),
        content: const Text(
          'Den ventende søknaden fjernes permanent. Dette kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await SupabaseService.deleteAbsence(_absence.id);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Søknaden er slettet')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(AbsenceStatus status) async {
    final commentCtrl = TextEditingController();
    final label = status == AbsenceStatus.godkjent ? 'Godkjenn' : 'Avvis';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label fravær'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_absence.userName ?? "Ansatt"} · ${_absence.type.label}',
              style: DriftProTheme.bodySm,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Kommentar (valgfritt)',
                hintText: 'Valgfri beskjed til ansatt',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: status == AbsenceStatus.godkjent
                  ? DriftProTheme.success
                  : DriftProTheme.error,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    try {
      if (widget.onDecide != null) {
        await widget.onDecide!(
          _absence.id,
          status,
          decisionComment: commentCtrl.text.trim(),
        );
      } else {
        await SupabaseService.updateAbsenceStatus(
          _absence.id,
          status,
          decisionComment: commentCtrl.text.trim(),
        );
        await widget.onChanged();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == AbsenceStatus.godkjent ? 'Godkjent' : 'Avvist',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      commentCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _absence;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(a.type.label, style: DriftProTheme.headingMd),
                ),
                _statusChip(a.status),
              ],
            ),
            if (a.userName != null && !_isOwner) ...[
              const SizedBox(height: 4),
              Text(a.userName!, style: DriftProTheme.labelLg),
            ],
            const SizedBox(height: 12),
            Text(
              '${DateFormat('d. MMM yyyy').format(a.startDate)} – '
              '${DateFormat('d. MMM yyyy').format(a.endDate)} (${widget.days} dager)',
              style: DriftProTheme.bodyMd,
            ),
            if (a.comment != null && a.comment!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Kommentar fra ansatt', style: DriftProTheme.labelSm),
              const SizedBox(height: 4),
              Text(a.comment!, style: DriftProTheme.bodySm),
            ],
            if (a.decisionComment != null && a.decisionComment!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Svar fra leder', style: DriftProTheme.labelSm),
              const SizedBox(height: 4),
              Text(a.decisionComment!, style: DriftProTheme.bodySm),
            ],
            if (_isPending && _isOwner) ...[
              const SizedBox(height: 8),
              Text(
                'Du kan endre eller slette søknaden så lenge den venter på behandling.',
                style: DriftProTheme.caption,
              ),
            ],
            const SizedBox(height: 20),
            if (_busy)
              const Center(child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ))
            else if (_isPending && _isOwner) ...[
              FilledButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Endre søknad'),
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
                label: const Text('Slett søknad', style: TextStyle(color: DriftProTheme.error)),
              ),
            ] else if (_isPending && _canManage) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decide(AbsenceStatus.avvist),
                      style: OutlinedButton.styleFrom(foregroundColor: DriftProTheme.error),
                      child: const Text('Avvis'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _decide(AbsenceStatus.godkjent),
                      style: FilledButton.styleFrom(backgroundColor: DriftProTheme.success),
                      child: const Text('Godkjenn'),
                    ),
                  ),
                ],
              ),
            ] else
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Lukk'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(AbsenceStatus status) {
    final color = switch (status) {
      AbsenceStatus.godkjent => DriftProTheme.success,
      AbsenceStatus.avvist => DriftProTheme.error,
      AbsenceStatus.ventende => DriftProTheme.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
