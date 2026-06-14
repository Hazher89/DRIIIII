import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_colors.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/theme/theme_notifier.dart';

const _themeModeOrder = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];

/// Kompakt utseende-rad i innstillinger + avansert panel for alle brukere.
class ThemeAppearancePicker extends StatelessWidget {
  const ThemeAppearancePicker({super.key});

  static Future<void> showAdvancedSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.driftColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _ThemeAppearanceAdvancedSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final themeNotifier = context.watch<ThemeNotifier>();
    final current = themeNotifier.themeMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: drift.card,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            leading: _ModeIconBadge(mode: current, size: 22),
            title: Text(
              'Utseende',
              style: DriftProTheme.bodyMd.copyWith(color: drift.textPrimary),
            ),
            subtitle: Text(
              _subtitle(current),
              style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
            ),
            trailing: TextButton.icon(
              onPressed: () => showAdvancedSheet(context),
              icon: Icon(Icons.tune_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
              label: Text(
                'Avansert',
                style: DriftProTheme.labelSm.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _ThemeModeSegment(
              current: current,
              onChanged: themeNotifier.setThemeMode,
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'Mørk modus — behagelig for øynene',
        ThemeMode.system => 'Følger enhetens innstilling',
        ThemeMode.light => 'Lys modus — klassisk DriftPro',
      };
}

class _ThemeModeSegment extends StatelessWidget {
  const _ThemeModeSegment({
    required this.current,
    required this.onChanged,
  });

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final primary = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: drift.surfaceMuted,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final mode in _themeModeOrder) ...[
              if (mode != _themeModeOrder.first) const SizedBox(width: 4),
              Expanded(
                child: _SegmentChip(
                  mode: mode,
                  selected: current == mode,
                  primary: primary,
                  onTap: () => onChanged(mode),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.mode,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
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
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? drift.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected ? Border.all(color: primary.withValues(alpha: 0.35)) : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? primary : drift.textMuted),
              const SizedBox(width: 5),
              Text(
                label,
                style: DriftProTheme.labelSm.copyWith(
                  color: selected ? primary : drift.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeAppearanceAdvancedSheet extends StatelessWidget {
  const _ThemeAppearanceAdvancedSheet();

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final themeNotifier = context.watch<ThemeNotifier>();
    final current = themeNotifier.themeMode;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
        children: [
          Text(
            'Utseende — avansert',
            style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Velg hvordan DriftPro skal se ut for deg. Innstillingen lagres på denne enheten.',
            style: DriftProTheme.bodySm.copyWith(color: drift.textMuted, height: 1.45),
          ),
          const SizedBox(height: 20),
          _LiveAppPreview(mode: current),
          const SizedBox(height: 20),
          for (final mode in _themeModeOrder) ...[
            _AdvancedThemeCard(
              mode: mode,
              selected: current == mode,
              onTap: () => themeNotifier.setThemeMode(mode),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: drift.surfaceMuted,
              borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
              border: Border.all(color: drift.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: drift.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      'Tips',
                      style: DriftProTheme.labelLg.copyWith(color: drift.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• System følger lys/mørk fra telefon eller PC\n'
                  '• Mørk modus reduserer belastning på øynene om kvelden\n'
                  '• Du kan bytte raskt med segmentene under «Utseende» i Innstillinger',
                  style: DriftProTheme.bodySm.copyWith(color: drift.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveAppPreview extends StatelessWidget {
  const _LiveAppPreview({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final preview = _previewPalette(mode, context);
    return Container(
      height: 132,
      decoration: BoxDecoration(
        gradient: preview.subtleGradient,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: preview.borderSubtle),
        boxShadow: preview.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: preview.heroGradient),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 72,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 48,
              left: 12,
              right: 12,
              child: Container(
                height: 68,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: preview.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: preview.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 110,
                      height: 8,
                      decoration: BoxDecoration(
                        color: preview.textPrimary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: preview.surfaceMuted,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 54,
                          height: 22,
                          decoration: BoxDecoration(
                            gradient: preview.heroGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedThemeCard extends StatelessWidget {
  const _AdvancedThemeCard({
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
    final preview = _previewPalette(mode, context);
    final primary = Theme.of(context).colorScheme.primary;

    final label = switch (mode) {
      ThemeMode.dark => 'Mørk',
      ThemeMode.system => 'System',
      ThemeMode.light => 'Lys',
    };
    final description = switch (mode) {
      ThemeMode.dark => 'Dempet bakgrunn og høy kontrast — ideelt i svakt lys.',
      ThemeMode.system => 'Bytter automatisk etter enhetens lys/mørk-innstilling.',
      ThemeMode.light => 'Klassisk DriftPro med lys bakgrunn og grønn profil.',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
            border: Border.all(
              color: selected ? primary : drift.borderSubtle,
              width: selected ? 2 : 1,
            ),
            color: selected ? primary.withValues(alpha: 0.06) : drift.card,
          ),
          child: Row(
            children: [
              _ModeIconBadge(mode: mode, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: DriftProTheme.labelLg.copyWith(
                        color: selected ? primary : drift.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: DriftProTheme.bodySm.copyWith(color: drift.textMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                height: 44,
                child: _MiniUiPreview(palette: preview),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, color: primary, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniUiPreview extends StatelessWidget {
  const _MiniUiPreview({required this.palette});

  final DriftProColors palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: palette.subtleGradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 5,
            left: 5,
            right: 5,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: palette.textPrimary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 5,
            right: 5,
            bottom: 5,
            child: Container(
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: palette.borderSubtle),
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            right: 7,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                gradient: palette.heroGradient,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeIconBadge extends StatelessWidget {
  const _ModeIconBadge({required this.mode, required this.size});

  final ThemeMode mode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final icon = switch (mode) {
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: drift.heroGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: size),
    );
  }
}

DriftProColors _previewPalette(ThemeMode mode, BuildContext context) {
  return switch (mode) {
    ThemeMode.dark => DriftProColors.dark,
    ThemeMode.light => DriftProColors.light,
    ThemeMode.system =>
      context.isDarkMode ? DriftProColors.dark : DriftProColors.light,
  };
}
