import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'case_trace.dart';

/// Viser sporings-ID og kort kode — kopierbar.
class CaseTraceChip extends StatelessWidget {
  const CaseTraceChip({
    super.key,
    required this.traceRef,
    required this.id,
    this.compact = false,
  });

  final String traceRef;
  final String id;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final code = CaseTrace.codeFromId(id);
    final label = compact ? '$traceRef · $code' : traceRef;

    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: '$traceRef ($code)'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sporings-ID kopiert: $traceRef')),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fingerprint, size: compact ? 12 : 14, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w800,
                  color: DriftProTheme.primaryGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                code,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
