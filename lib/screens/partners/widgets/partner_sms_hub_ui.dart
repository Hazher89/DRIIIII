import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'partner_modern_ui.dart';

/// Kompakt topp for Send-fanen — uten stor hero eller handlingsrutenett.
class PartnerSmsHubHeader extends StatelessWidget {
  const PartnerSmsHubHeader({
    super.key,
    required this.partnerCount,
    required this.activePartners,
  });

  final int partnerCount;
  final int activePartners;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerModernUi.muted(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.sms_rounded,
              color: DriftProTheme.primaryGreenDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send SMS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Til kontakter eller kunder fra rute-PDF. '
                  'Logg og innstillinger ligger i fanene over.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _metaChip(context, '$activePartners aktive'),
                    _metaChip(context, '$partnerCount bedrifter'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: PartnerModernUi.textPrimary(context),
        ),
      ),
    );
  }
}

/// Synlig stegindikator 1–4 for send-flyten.
class PartnerSmsStepStrip extends StatelessWidget {
  const PartnerSmsStepStrip({
    super.key,
    required this.currentStep,
    this.labels = const ['MAVI', 'Mottakere', 'Melding', 'Send'],
  });

  /// 0-basert aktivt steg (0–3).
  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerModernUi.muted(context);
    final active = DriftProTheme.primaryGreenDark;
    final done = DriftProTheme.primaryGreen;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Container(
                    height: 2,
                    color: i <= currentStep
                        ? done.withValues(alpha: 0.45)
                        : PartnerModernUi.border(context),
                  ),
                ),
              ),
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < currentStep
                        ? done
                        : i == currentStep
                            ? active
                            : PartnerModernUi.surface(context),
                    border: Border.all(
                      color: i <= currentStep
                          ? done
                          : PartnerModernUi.border(context),
                      width: 1.5,
                    ),
                  ),
                  child: i < currentStep
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: i == currentStep ? Colors.white : muted,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 64,
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          i == currentStep ? FontWeight.w800 : FontWeight.w600,
                      color: i == currentStep ? active : muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Seksjonskort rundt et steg i send-flyten.
class PartnerSmsSectionCard extends StatelessWidget {
  const PartnerSmsSectionCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.active = false,
  });

  final int step;
  final String title;
  final String? subtitle;
  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final border = active
        ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
        : PartnerModernUi.border(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: active ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? DriftProTheme.primaryGreen
                      : DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$step',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : DriftProTheme.primaryGreenDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: PartnerModernUi.muted(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
