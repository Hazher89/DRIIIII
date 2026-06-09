import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Fast «Lagre»-linje nederst på stempling-faner med redigerbare felt.
class StemplingSaveBar extends StatelessWidget {
  const StemplingSaveBar({
    super.key,
    required this.onSave,
    this.saving = false,
    this.dirty = true,
    this.label = 'Lagre endringer',
  });

  final VoidCallback onSave;
  final bool saving;
  final bool dirty;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dirty ? 'Ulagrede endringer' : 'Alle endringer er lagret',
                  style: TextStyle(
                    fontSize: 13,
                    color: dirty ? DriftProTheme.warning : Colors.grey.shade600,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: saving || !dirty ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'Lagrer…' : label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
