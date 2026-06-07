import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum DmsExplorerSection { home, shared, starred, recent }

class DmsExplorerSidebar extends StatelessWidget {
  final DmsExplorerSection section;
  final ValueChanged<DmsExplorerSection> onSectionChanged;
  final int folderCount;
  final int fileCount;
  final int sharedCount;
  final int starredCount;
  final String storageLabel;
  final bool compact;

  const DmsExplorerSidebar({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.folderCount,
    required this.fileCount,
    required this.sharedCount,
    required this.starredCount,
    required this.storageLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact ? 200.0 : 240.0;
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? DriftProTheme.cardDark
          : const Color(0xFFF4F6F8),
      child: SizedBox(
        width: width,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          children: [
            Text('Dokumenter', style: DriftProTheme.headingSm),
            const SizedBox(height: 4),
            Text(
              storageLabel,
              style: DriftProTheme.caption,
            ),
            const SizedBox(height: 16),
            _navTile(
              icon: Icons.home_outlined,
              label: 'Hovedarkiv',
              subtitle: '$folderCount mapper · $fileCount filer',
              value: DmsExplorerSection.home,
            ),
            _navTile(
              icon: Icons.groups_outlined,
              label: 'Felles mapper',
              subtitle: 'Alle MAVI-ansatte',
              badge: sharedCount > 0 ? '$sharedCount' : null,
              value: DmsExplorerSection.shared,
            ),
            _navTile(
              icon: Icons.star_outline,
              label: 'Stjernemerkede',
              badge: starredCount > 0 ? '$starredCount' : null,
              value: DmsExplorerSection.starred,
            ),
            _navTile(
              icon: Icons.schedule_outlined,
              label: 'Nylige filer',
              value: DmsExplorerSection.recent,
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Text('Tips', style: DriftProTheme.labelSm),
            const SizedBox(height: 6),
            Text(
              'Dra filer hit for opplasting. Høyreklikk / langt trykk for meny.',
              style: DriftProTheme.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String label,
    required DmsExplorerSection value,
    String? subtitle,
    String? badge,
  }) {
    final selected = section == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: selected ? DriftProTheme.primaryGreen.withValues(alpha: 0.12) : null,
        leading: Icon(
          icon,
          color: selected ? DriftProTheme.primaryGreen : null,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 11))
            : null,
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(badge, style: const TextStyle(fontSize: 11)),
              )
            : null,
        onTap: () => onSectionChanged(value),
      ),
    );
  }
}
