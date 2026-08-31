import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';

/// Stor opplastingsflate når ingen PDF er valgt ennå.
class RouteWorkflowUploadHero extends StatelessWidget {
  const RouteWorkflowUploadHero({
    super.key,
    required this.accent,
    required this.onUpload,
    this.busy = false,
    this.title = 'Last opp rute-PDF',
    this.subtitle =
        'Systemet leser MAVI-kode, dato, skift og starttid automatisk. '
        'Du kontrollerer før du sender.',
  });

  final Color accent;
  final VoidCallback? onUpload;
  final bool busy;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Material(
      color: accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: busy ? null : onUpload,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: busy
                    ? SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accent,
                        ),
                      )
                    : Icon(Icons.cloud_upload_outlined, size: 40, color: accent),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: drift.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.45, color: drift.textMuted),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy ? null : onUpload,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                icon: const Icon(Icons.upload_file),
                label: Text(busy ? 'Leser PDF…' : 'Velg PDF-fil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vises etter vellykket publisering.
class RouteWorkflowSuccessPanel extends StatelessWidget {
  const RouteWorkflowSuccessPanel({
    super.key,
    required this.title,
    required this.message,
    required this.accent,
    this.detail,
    this.onDone,
  });

  final String title;
  final String message;
  final String? detail;
  final Color accent;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, size: 56, color: Colors.green.shade700),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: drift.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: drift.textMuted),
            ),
            if (detail != null) ...[
              const SizedBox(height: 12),
              Material(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: drift.textSecondary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onDone ?? () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                minimumSize: const Size(double.infinity, 48),
              ),
              icon: const Icon(Icons.done_all),
              label: const Text('Ferdig — tilbake til planlegger'),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteWorkflowStepRail extends StatelessWidget {
  const RouteWorkflowStepRail({
    super.key,
    required this.steps,
    required this.activeIndex,
    this.accent = DriftProTheme.primaryGreen,
  });

  final List<String> steps;
  final int activeIndex;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= activeIndex ? accent : Colors.grey.shade300,
              ),
            ),
          _dot(i + 1, steps[i], i <= activeIndex),
        ],
      ],
    );
  }

  Widget _dot(int n, String label, bool active) {
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: active ? accent : Colors.grey.shade300,
          child: Text(
            '$n',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
