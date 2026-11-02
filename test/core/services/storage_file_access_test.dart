import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/storage/storage_file_access.dart';

void main() {
  test('normalizeDropboxPath handles dropbox:/// and missing slash', () {
    expect(
      StorageFileAccess.normalizeDropboxPath(
        'dropbox:///company_00000000-0000-0000-0000-000000000000/routes/a.pdf',
      ),
      '/company_00000000-0000-0000-0000-000000000000/routes/a.pdf',
    );
    expect(
      StorageFileAccess.normalizeDropboxPath(
        'company_00000000-0000-0000-0000-000000000000/routes/a.pdf',
      ),
      '/company_00000000-0000-0000-0000-000000000000/routes/a.pdf',
    );
  });

  test('candidateSupabasePaths ignores dropbox references', () {
    final paths = StorageFileAccess.candidateSupabasePaths(
      'dropbox:///company_00000000-0000-0000-0000-000000000000/routes/a.pdf',
      companyId: '00000000-0000-0000-0000-000000000000',
    );
    expect(paths, isEmpty);
  });
}
