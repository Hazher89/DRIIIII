import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_colors.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/theme/theme_notifier.dart';

/// Avansert temavelger: Lys / Mørk / System med forhåndsvisning.
class ThemeAppearancePicker extends StatelessWidget {
  const ThemeAppearancePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final themeNotifier = context.watch<ThemeNotifier>();
    final current = themeNotifier.themeMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: drift.card,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: drift.borderSubtle),
        boxShadow: drift.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: drift.heroGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  current == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : current == ThemeMode.light
                          ? Icons.light_mode_rounded
                          : Icons.brightness_auto_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Utseende',
                      style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(current),
                      style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              return compact
                  ? Column(
                      children: [
                        _ThemeOptionCard(
                          mode: ThemeMode.light,
                          selected: current == ThemeMode.light,
                          onTap: () => themeNotifier.setThemeMode(ThemeMode.light),
                        ),
                        const SizedBox(height: 8),
                        _ThemeOptionCard(
                          mode: ThemeMode.dark,
                          selected: current == ThemeMode.dark,
                          onTap: () => themeNotifier.setThemeMode(ThemeMode.dark),
                        ),
                        const SizedBox(height: 8),
                        _ThemeOptionCard(
                          mode: ThemeMode.system,
                          selected: current == ThemeMode.system,
                          onTap: () => themeNotifier.setThemeMode(ThemeMode.system),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _ThemeOptionCard(
                            mode: ThemeMode.light,
                            selected: current == ThemeMode.light,
                            onTap: () => themeNotifier.setThemeMode(ThemeMode.light),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ThemeOptionCard(
                            mode: ThemeMode.dark,
                            selected: current == ThemeMode.dark,
                            onTap: () => themeNotifier.setThemeMode(ThemeMode.dark),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ThemeOptionCard(
                            mode: ThemeMode.system,
                            selected: current == ThemeMode.system,
                            onTap: () => themeNotifier.setThemeMode(ThemeMode.system),
                          ),
                        ),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  String _subtitle(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'Mørk modus — behagelig for øynene',
        ThemeMode.system => 'Følger enhetens innstilling',
        ThemeMode.light => 'Lys modus — klassisk DriftPro',
      };
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final preview = mode == ThemeMode.dark
        ? DriftProColors.dark
        : mode == ThemeMode.light
            ? DriftProColors.light
            : (context.isDarkMode ? DriftProColors.dark : DriftProColors.light);

    final label = switch (mode) {
      ThemeMode.dark => 'Mørk',
      ThemeMode.system => 'System',
      ThemeMode.light => 'Lys',
    };

    final icon = switch (mode) {
      ThemeMode.dark => Icons.nights_stay_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.wb_sunny_rounded,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : drift.borderSubtle,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : drift.surfaceMuted,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: preview.subtleGradient,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: preview.borderSubtle),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        width: 28,
                        height: 6,
                        decoration: BoxDecoration(
                          color: preview.textPrimary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: preview.card,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: preview.borderSubtle),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 8,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          gradient: preview.heroGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : drift.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: DriftProTheme.labelSm.copyWith(
                      color: selected ? Theme.of(context).colorScheme.primary : drift.textSecondary,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
