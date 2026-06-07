import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// Ansatt registrerer antall barn under 12 — styrer sykt-barn-kvote automatisk.
class ProfileChildrenUnder12Card extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback? onSaved;

  const ProfileChildrenUnder12Card({
    super.key,
    required this.profile,
    this.onSaved,
  });

  @override
  State<ProfileChildrenUnder12Card> createState() =>
      _ProfileChildrenUnder12CardState();
}

class _ProfileChildrenUnder12CardState extends State<ProfileChildrenUnder12Card> {
  late int _count;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _count = widget.profile.childrenUnder12Count;
  }

  int get _syktBarnLimit => LeaveRules.syktBarnDaysLimit(_count);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SupabaseService.updateProfileChildrenUnder12(
        profileId: widget.profile.id,
        count: _count,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Antall barn lagret')),
        );
        widget.onSaved?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.family_restroom_outlined,
                  color: DriftProTheme.primaryGreen),
              const SizedBox(width: 10),
              Text('Barn under 12 år', style: DriftProTheme.labelLg),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Brukes til sykt-barn-kvote: '
            '${LeaveRules.syktBarnDaysPerChildUnder12} dager (1 barn) eller '
            '${LeaveRules.syktBarnDaysTwoOrMoreChildren} dager (2+ barn) per '
            '12-måneders periode. Kilde: folketrygdloven kap. 5 (Lovdata).',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.filled(
                onPressed: _count > 0 && !_saving
                    ? () => setState(() => _count--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 16),
              Text(
                '$_count',
                style: DriftProTheme.headingMd,
              ),
              const SizedBox(width: 16),
              IconButton.filled(
                onPressed: _count < 12 && !_saving
                    ? () => setState(() => _count++)
                    : null,
                icon: const Icon(Icons.add),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: DriftProTheme.absenceSickChild.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Sykt barn: $_syktBarnLimit d/år',
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (_count != widget.profile.childrenUnder12Count) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lagre antall barn'),
            ),
          ],
        ],
      ),
    );
  }
}
