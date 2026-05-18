import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/dms/dms_file_editor_service.dart';
import '../../core/services/dms/dms_print_service.dart';
import '../../core/services/dms/dms_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_type_resolver.dart';
import '../../core/utils/office_file_type.dart';
import '../../models/dms/dms_file.dart';
import 'preview/document_text_editor.dart';
import 'preview/excel_sheet_editor.dart';
import '../../widgets/platform_embedded_view.dart';
import '../../widgets/platform_media_view.dart';
import '../../widgets/platform_pdf_view.dart';

class FileViewerScreen extends StatefulWidget {
  final DmsFile file;
  const FileViewerScreen({super.key, required this.file});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  static const _maxBytes = 25 * 1024 * 1024;

  final _excelKey = GlobalKey<ExcelSheetEditorState>();
  final _textKey = GlobalKey<DocumentTextEditorState>();

  String? _url;
  List<int>? _bytes;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _dirty = false;
  String? _error;
  FilePreviewKind? _kind;
  String? _contentType;
  String? _resolvedExt;
  OfficeFileType _officeType = OfficeFileType.unknown;

  bool get _canEdit =>
      _kind == FilePreviewKind.office ||
      _kind == FilePreviewKind.text ||
      _officeType == OfficeFileType.excel ||
      _officeType == OfficeFileType.word ||
      _officeType == OfficeFileType.csv;

  bool get _isExcel =>
      _officeType == OfficeFileType.excel ||
      _resolvedExt == 'xlsx' ||
      _resolvedExt == 'xls';

  bool get _isWordOrText =>
      _officeType == OfficeFileType.word ||
      _kind == FilePreviewKind.text ||
      _officeType == OfficeFileType.csv;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      _resolvedExt = widget.file.resolvedExtension ??
          FileTypeResolver.extensionFromName(widget.file.name) ??
          FileTypeResolver.extensionFromStoragePath(widget.file.storagePath);

      _officeType = OfficeFileTypeHelper.fromExtension(_resolvedExt);

      final url = await DmsService.getDownloadUrl(widget.file.storagePath);
      var response = await http.get(
        Uri.parse(url),
        headers: const {'Range': 'bytes=0-8191'},
      );
      if (response.statusCode != 206 && response.statusCode != 200) {
        response = await http.get(Uri.parse(url));
      }

      var sample = response.bodyBytes;
      if (sample.length > 8192) sample = sample.sublist(0, 8192);

      final contentType = response.headers['content-type'];
      var kind = FileTypeResolver.resolve(
        fileName: widget.file.name,
        storagePath: widget.file.storagePath,
        storedExtension: widget.file.extension,
        contentType: contentType,
        magicBytes: sample,
      );

      final needsFullBytes = kind == FilePreviewKind.office ||
          _officeType != OfficeFileType.unknown ||
          kind == FilePreviewKind.pdf ||
          kind == FilePreviewKind.image ||
          kind == FilePreviewKind.text;

      List<int>? fullBytes;
      if (needsFullBytes) {
        fullBytes = response.bodyBytes.length >= 8192
            ? (await http.get(Uri.parse(url))).bodyBytes
            : List<int>.from(response.bodyBytes);
        if (fullBytes.length > _maxBytes) {
          throw Exception(
            'Filen er for stor (${(fullBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
            'Maks ${_maxBytes ~/ 1024 ~/ 1024} MB.',
          );
        }
      }

      if (_officeType != OfficeFileType.unknown ||
          kind == FilePreviewKind.office) {
        kind = FilePreviewKind.office;
      }

      if (!mounted) return;
      setState(() {
        _url = url;
        _bytes = fullBytes;
        _kind = kind;
        _contentType = contentType;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _download() async {
    if (_url == null) return;
    await launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication);
  }

  Future<void> _print() async {
    try {
      final name = widget.file.name;
      if (_kind == FilePreviewKind.pdf && _bytes != null) {
        await DmsPrintService.printPdfBytes(
          Uint8List.fromList(_bytes!),
          name: name,
        );
        return;
      }
      if (_kind == FilePreviewKind.image && _bytes != null) {
        await DmsPrintService.printImage(
          Uint8List.fromList(_bytes!),
          title: name,
        );
        return;
      }
      if (_isExcel && _excelKey.currentState != null) {
        await DmsPrintService.printSpreadsheet(
          sheets: _excelKey.currentState!.exportSheets(),
          title: name,
        );
        return;
      }
      if (_isWordOrText && _textKey.currentState != null) {
        await DmsPrintService.printText(
          text: _textKey.currentState!.text,
          title: name,
        );
        return;
      }
      if (_bytes != null && FileTypeResolver.isLikelyText(_bytes!)) {
        await DmsPrintService.printText(
          text: String.fromCharCodes(_bytes!),
          title: name,
        );
        return;
      }
      if (_bytes != null) {
        await DmsPrintService.printPdfBytes(
          Uint8List.fromList(_bytes!),
          name: name,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Utskrift feilet: $e')),
        );
      }
    }
  }

  Future<void> _save({required bool replaceOriginal}) async {
    if (_bytes == null) return;
    setState(() => _isSaving = true);
    try {
      final companyId = widget.file.companyId;
      Uint8List out;
      String fileName = widget.file.name;

      if (_isExcel && _excelKey.currentState != null) {
        out = _excelKey.currentState!.exportXlsxBytes();
        if (!fileName.toLowerCase().endsWith('.xlsx')) {
          fileName = '$fileName.xlsx';
        }
      } else if (_isWordOrText && _textKey.currentState != null) {
        final ext = _resolvedExt?.toLowerCase();
        if (ext == 'docx') {
          out = _textKey.currentState!.exportBytes(asDocx: true);
        } else {
          out = _textKey.currentState!.exportBytes();
        }
      } else {
        out = Uint8List.fromList(_bytes!);
      }

      if (replaceOriginal) {
        await DmsFileEditorService.replaceFile(
          file: widget.file,
          bytes: out,
          newFileName: fileName,
        );
      } else {
        final base = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
        final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
        final newName =
            '${base}_redigert_${DateTime.now().millisecondsSinceEpoch}$ext';
        await DmsFileEditorService.saveAsNewFile(
          bytes: out,
          fileName: newName,
          companyId: companyId,
          folderId: widget.file.folderId,
        );
      }

      if (!mounted) return;
      setState(() {
        _dirty = false;
        _bytes = out;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            replaceOriginal
                ? 'Filen er oppdatert i arkivet'
                : 'Lagret som ny fil i samme mappe',
          ),
        ),
      );
      if (replaceOriginal) {
        await _prepare();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lagring feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSaveMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save, color: DriftProTheme.primaryGreen),
              title: const Text('Erstatt originalfil'),
              subtitle: const Text('Oppdaterer filen i arkivet'),
              onTap: () {
                Navigator.pop(ctx);
                _save(replaceOriginal: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_as_outlined),
              title: const Text('Lagre som ny fil'),
              subtitle: const Text('Beholder original + ny kopi'),
              onTap: () {
                Navigator.pop(ctx);
                _save(replaceOriginal: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ulagrede endringer'),
        content: const Text('Vil du lukke uten å lagre?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lukk')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSaveMenu();
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _onWillPop() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? DriftProTheme.bgDark : Colors.grey[100],
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await _onWillPop() && mounted) Navigator.pop(context);
            },
          ),
          title: Text(widget.file.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Skriv ut / PDF-utskrift',
              onPressed: _isLoading ? null : _print,
            ),
            if (_canEdit)
              IconButton(
                icon: Icon(_dirty ? Icons.save : Icons.save_outlined),
                tooltip: 'Lagre endringer',
                onPressed: _isSaving || !_dirty ? null : _showSaveMenu,
              ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Last ned',
              onPressed: _url == null ? null : _download,
            ),
            if (_canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _showSaveMenu,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_document),
                  label: const Text('Lagre'),
                ),
              ),
          ],
        ),
        body: _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Laster dokument…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (_url != null)
                ElevatedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download),
                  label: const Text('Last ned fil'),
                ),
            ],
          ),
        ),
      );
    }
    if (_url == null || _bytes == null) {
      return const Center(child: Text('Kunne ikke hente fil'));
    }

    return Column(
      children: [
        if (_dirty)
          Material(
            color: Colors.orange.shade100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: Colors.orange.shade900, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Redigeringsmodus – lagre erstatter filen eller oppretter kopi',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: _buildPreview(_kind ?? FilePreviewKind.universal, _url!)),
      ],
    );
  }

  Widget _buildPreview(FilePreviewKind kind, String url) {
    final bytes = Uint8List.fromList(_bytes!);

    if (_isExcel) {
      return ExcelSheetEditor(
        key: _excelKey,
        bytes: bytes,
        isXls: _resolvedExt == 'xls',
        onChanged: (_) => setState(() => _dirty = true),
      );
    }

    if (_isWordOrText ||
        kind == FilePreviewKind.text ||
        _officeType == OfficeFileType.word) {
      return DocumentTextEditor(
        key: _textKey,
        bytes: bytes,
        extension: _resolvedExt,
        onChanged: (_) => setState(() => _dirty = true),
      );
    }

    switch (kind) {
      case FilePreviewKind.pdf:
        return PlatformPdfView(url: url);

      case FilePreviewKind.image:
        return Center(
          child: InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        );

      case FilePreviewKind.office:
        return ExcelSheetEditor(
          key: _excelKey,
          bytes: bytes,
          onChanged: (_) => setState(() => _dirty = true),
        );

      case FilePreviewKind.video:
        return PlatformMediaView(url: url);

      case FilePreviewKind.audio:
        return PlatformMediaView(url: url, isAudio: true);

      case FilePreviewKind.text:
        return DocumentTextEditor(
          key: _textKey,
          bytes: bytes,
          extension: _resolvedExt,
          onChanged: (_) => setState(() => _dirty = true),
        );

      case FilePreviewKind.universal:
        return PlatformEmbeddedView(url: url, mimeHint: _contentType);
    }
  }
}
