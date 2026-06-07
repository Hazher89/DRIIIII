import 'package:flutter/material.dart';

import '../../../core/services/dms/dms_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/dms/dms_file.dart';
import '../../../models/dms/dms_folder.dart';

class DmsMoveFileSheet extends StatelessWidget {
  final DmsFile file;
  final String companyId;
  final List<DmsFolder> folders;

  const DmsMoveFileSheet({
    super.key,
    required this.file,
    required this.companyId,
    required this.folders,
  });

  static Future<bool?> show(
    BuildContext context, {
    required DmsFile file,
    required String companyId,
    required List<DmsFolder> folders,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DmsMoveFileSheet(
        file: file,
        companyId: companyId,
        folders: folders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<DmsFolder>.from(folders)
      ..sort((a, b) => a.name.compareTo(b.name));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Flytt «${file.name}»', style: DriftProTheme.headingMd),
            const SizedBox(height: 8),
            Text(
              'Velg målmappe',
              style: DriftProTheme.caption,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Hovedarkiv (rot)'),
              onTap: () async {
                await DmsService.moveFile(file.id, null);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final f = sorted[i];
                  if (f.id == file.folderId) return const SizedBox.shrink();
                  return ListTile(
                    leading: Icon(
                      f.isSharedMavi ? Icons.groups_outlined : Icons.folder_outlined,
                      color: Colors.amber.shade700,
                    ),
                    title: Text(f.name),
                    subtitle: f.isSharedMavi
                        ? const Text('Felles mappe')
                        : null,
                    onTap: () async {
                      await DmsService.moveFile(file.id, f.id);
                      if (context.mounted) Navigator.pop(context, true);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
