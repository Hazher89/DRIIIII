import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/vision_camera.dart';

/// Fotogalleri for uniform-brudd — bilde, dato og tid.
class UniformViolationsGallery extends StatelessWidget {
  const UniformViolationsGallery({
    super.key,
    required this.violations,
    required this.onRefresh,
  });

  final List<VisionEvent> violations;
  final Future<void> Function() onRefresh;

  static final _timeFmt = DateFormat('dd.MM.yyyy');
  static final _clockFmt = DateFormat('HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (violations.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 72),
            Icon(
              Icons.check_circle_outline,
              size: 52,
              color: scheme.primary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'Ingen uniform-brudd registrert',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                'Når noen mangler MAVI-logo eller vernesko lagres et bilde her med dato og klokkeslett.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: violations.length,
        itemBuilder: (context, i) => _ViolationTile(
          event: violations[i],
          dateLabel: _timeFmt.format(violations[i].occurredAt.toLocal()),
          timeLabel: _clockFmt.format(violations[i].occurredAt.toLocal()),
          onTap: () => _openPreview(context, violations[i]),
        ),
      ),
    );
  }

  Future<void> _openPreview(BuildContext context, VisionEvent event) async {
    final url = event.dropboxImageUrl;
    if (url.isEmpty) return;
    final local = event.occurredAt.toLocal();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(event.violationSummary),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '${_timeFmt.format(local)} ${_clockFmt.format(local)}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
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

class _ViolationTile extends StatelessWidget {
  const _ViolationTile({
    required this.event,
    required this.dateLabel,
    required this.timeLabel,
    required this.onTap,
  });

  final VisionEvent event;
  final String dateLabel;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = event.dropboxImageUrl;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: url.isEmpty
                  ? ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_off_outlined,
                        size: 40,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              color: scheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.violationSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 12, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dateLabel,
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (event.missingLogo)
                        _Tag(
                          label: 'Logo',
                          color: DriftProTheme.warning,
                        ),
                      if (event.missingShoes)
                        _Tag(
                          label: 'Vernesko',
                          color: scheme.error,
                        ),
                    ],
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
