import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';

class _LiftSection {
  const _LiftSection({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.bullets,
    this.warning = false,
  });

  final String asset;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final bool warning;
}

/// Pedagogisk guide for tungløft / manuell håndtering (BHT / Grønn Jobb).
class TungloftGuideScreen extends StatelessWidget {
  const TungloftGuideScreen({super.key});

  static const _sections = [
    _LiftSection(
      asset: 'assets/hms/tungloft/tungloft_riktig_loft.png',
      title: 'Riktig løfteteknikk',
      subtitle: 'Slik beskytter du rygg og skuldre',
      bullets: [
        'Stå stabilt med føttene i skulderbredde',
        'Bøy knærne — hold ryggen så rett som mulig',
        'Hold lasten tett inntil kroppen',
        'Løft med beina, ikke med ryggen',
      ],
    ),
    _LiftSection(
      asset: 'assets/hms/tungloft/tungloft_feil_loft.png',
      title: 'Unngå dette',
      subtitle: 'Typiske feil som gir skader',
      warning: true,
      bullets: [
        'Ikke løft med krum og vridd rygg',
        'Ikke strekk armen langt ut med tung last',
        'Ikke løft over skulderhøyde uten hjelpemiddel',
        'Ikke ta «bare denne ene» hvis den er for tung',
      ],
    ),
    _LiftSection(
      asset: 'assets/hms/tungloft/tungloft_trapp.png',
      title: 'Bæring og trapper',
      subtitle: 'Spesielt ved hjemlevering og montering',
      bullets: [
        'Planlegg ruten før du løfter — rydd veien',
        'Bruk to personer på store hvitevarer',
        'Gå i takt i trapp; kommuniser klart',
        'Sett fra deg lasten trygt før du hviler',
      ],
    ),
    _LiftSection(
      asset: 'assets/hms/tungloft/tungloft_hjelpemiddel.png',
      title: 'Bruk hjelpemidler',
      subtitle: 'Tralle, truck og løfteutstyr først',
      bullets: [
        'Velg tralle / sekketralle når det er mulig',
        'Kontroller at hjelpemiddelet er i orden',
        'Fordel lasten jevnt — ikke overlast',
        'Be om truck eller løftebord ved tunge kolli',
      ],
    ),
    _LiftSection(
      asset: 'assets/hms/tungloft/tungloft_stopp_hjelp.png',
      title: 'Stopp og be om hjelp',
      subtitle: 'Du har rett — og plikt — til å si nei',
      bullets: [
        'Er lasten for tung, ustabil eller vanskelig å gripe: stopp',
        'Be en kollega om to-person løft',
        'Meld fra hvis hjelpemidler mangler',
        'Registrer nesten-uhell / avvik så vi kan forbedre',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF7F8F6);
    final cardBg = isDark ? DriftProTheme.cardDark : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Tungløft'),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Hero(isDark: isDark),
          const SizedBox(height: 16),
          _TrafficLightCard(isDark: isDark),
          const SizedBox(height: 20),
          for (final s in _sections) ...[
            _SectionCard(section: s, cardBg: cardBg, isDark: isDark),
            const SizedBox(height: 16),
          ],
          Text(
            'Neste steg i systematisk HMS',
            style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => context.push(AppPaths.hmsRisiko),
                icon: const Icon(Icons.assessment_outlined, size: 18),
                label: const Text('Opprett risikoanalyse'),
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push(AppPaths.hmsVernerunde),
                icon: const Icon(Icons.checklist_rtl, size: 18),
                label: const Text('Start vernerunde'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push(AppPaths.hmsHandbokDoc('tungloft')),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Vedlegg 12 (instruks)'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Opplæring her erstatter ikke risikovurdering. Bruk malene under Risiko '
            'og sjekkpunktene i Vernerunde for å dokumentere arbeidet.',
            style: DriftProTheme.caption.copyWith(
              color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.5),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen,
            DriftProTheme.primaryGreen.withValues(alpha: 0.82),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tungløft og manuell håndtering',
                  style: DriftProTheme.headingSm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Basert på MAVI Logistikk sin instruks for tunge løft (vedlegg 12). '
            'Bruk hjelpemidler når det er mulig — alltid når håndteringen innebærer helsefare.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.45,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficLightCard extends StatelessWidget {
  const _TrafficLightCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? DriftProTheme.cardDark : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vurder før du løfter (MAVI)',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _zone(
            Colors.green.shade700,
            'Grønt',
            'Løft kan vanligvis utføres uten risiko.',
          ),
          _zone(
            Colors.amber.shade800,
            'Gult',
            'Kan være skadelig (form, høyde, hyppighet). Vurder hjelpemidler. '
            'Ved bæring over 2 m, asymmetrisk last eller trange forhold: bruk hjelpemidler.',
          ),
          _zone(
            Colors.red.shade700,
            'Rødt',
            'Belastning kan være skadelig — hjelpemidler må brukes.',
          ),
          const SizedBox(height: 6),
          Text(
            'Samlet daglig vekt: maks ca. 6 tonn stående / 3 tonn sittende. '
            'Bæring over 3 kg skal være tett på kroppen.',
            style: DriftProTheme.caption.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _zone(Color color, String title, String body) {
    final ink = isDark
        ? Colors.white.withValues(alpha: 0.88)
        : const Color(0xFF1A1A1A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: ink,
                ),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.cardBg,
    required this.isDark,
  });

  final _LiftSection section;
  final Color cardBg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = section.warning ? DriftProTheme.error : DriftProTheme.primaryGreen;

    return Material(
      color: cardBg,
      elevation: isDark ? 0 : 0.5,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.asset(
                  section.asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  cacheWidth: 720,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, error, stackTrace) => Container(
                    color: accent.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: Icon(Icons.image_outlined, color: accent, size: 36),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: DriftProTheme.headingSm.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        section.subtitle,
                        style: DriftProTheme.caption.copyWith(
                          color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final b in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      section.warning
                          ? Icons.close_rounded
                          : Icons.check_circle_outline,
                      size: 18,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b,
                        style: const TextStyle(height: 1.35, fontSize: 14.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
