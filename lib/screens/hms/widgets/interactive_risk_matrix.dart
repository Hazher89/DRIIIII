import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Interaktiv 5×5 risikomatrise — trykk for å velge S/K.
class InteractiveRiskMatrix extends StatelessWidget {
  final int selectedProbability;
  final int selectedConsequence;
  final ValueChanged<int>? onProbabilityChanged;
  final ValueChanged<int>? onConsequenceChanged;
  final String title;
  final bool readOnly;

  const InteractiveRiskMatrix({
    super.key,
    required this.selectedProbability,
    required this.selectedConsequence,
    this.onProbabilityChanged,
    this.onConsequenceChanged,
    this.title = 'Risikomatrise',
    this.readOnly = false,
  });

  Color _cellColor(int score, bool isDark) {
    if (score <= 4) {
      return isDark ? Colors.green.shade900 : Colors.green.shade100;
    }
    if (score <= 9) {
      return isDark ? Colors.yellow.shade900 : Colors.yellow.shade100;
    }
    if (score <= 14) {
      return isDark ? Colors.orange.shade900 : Colors.orange.shade200;
    }
    return isDark ? Colors.red.shade900 : Colors.red.shade200;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final score = selectedProbability * selectedConsequence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: DriftProTheme.headingSm),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _cellColor(score, isDark),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'S$selectedProbability × K$selectedConsequence = $score',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(width: 36),
            ...List.generate(
              5,
              (c) => Expanded(
                child: Center(
                  child: Text(
                    'K${c + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ...List.generate(5, (row) {
          final p = 5 - row;
          return Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  'S$p',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ...List.generate(5, (col) {
                final c = col + 1;
                final cellScore = p * c;
                final selected =
                    p == selectedProbability && c == selectedConsequence;
                return Expanded(
                  child: GestureDetector(
                    onTap: readOnly
                        ? null
                        : () {
                            onProbabilityChanged?.call(p);
                            onConsequenceChanged?.call(c);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 48,
                      margin: const EdgeInsets.all(2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _cellColor(cellScore, isDark),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? DriftProTheme.primaryGreen
                              : Colors.transparent,
                          width: selected ? 3 : 0,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: DriftProTheme.primaryGreen
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check, size: 18)
                          : null,
                    ),
                  ),
                );
              }),
            ],
          );
        }),
        const SizedBox(height: 8),
        Text(
          'Sannsynlighet (S) × Konsekvens (K). Grønn = lav, rød = høy.',
          style: DriftProTheme.bodySm.copyWith(
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

/// Side-om-side initial vs rest-risiko.
class DualRiskMatrixPanel extends StatelessWidget {
  final int initialP;
  final int initialC;
  final int residualP;
  final int residualC;
  final ValueChanged<int>? onInitialP;
  final ValueChanged<int>? onInitialC;
  final ValueChanged<int>? onResidualP;
  final ValueChanged<int>? onResidualC;
  final bool readOnly;

  const DualRiskMatrixPanel({
    super.key,
    required this.initialP,
    required this.initialC,
    required this.residualP,
    required this.residualC,
    this.onInitialP,
    this.onInitialC,
    this.onResidualP,
    this.onResidualC,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        final initial = InteractiveRiskMatrix(
          title: 'Initial risiko (nå)',
          selectedProbability: initialP,
          selectedConsequence: initialC,
          onProbabilityChanged: onInitialP,
          onConsequenceChanged: onInitialC,
          readOnly: readOnly,
        );
        final residual = InteractiveRiskMatrix(
          title: 'Rest-risiko (etter tiltak)',
          selectedProbability: residualP,
          selectedConsequence: residualC,
          onProbabilityChanged: onResidualP,
          onConsequenceChanged: onResidualC,
          readOnly: readOnly,
        );

        if (stacked) {
          return Column(
            children: [
              initial,
              const SizedBox(height: 24),
              residual,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: initial),
            const SizedBox(width: 16),
            Expanded(child: residual),
          ],
        );
      },
    );
  }
}
