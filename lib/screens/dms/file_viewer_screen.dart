import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../models/dms/dms_file.dart';
import '../../core/services/dms/dms_service.dart';
import 'dart:ui_web' as ui;
import 'dart:html' as html;

class FileViewerScreen extends StatefulWidget {
  final DmsFile file;
  const FileViewerScreen({super.key, required this.file});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  String? _url;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    try {
      final url = await DmsService.getDownloadUrl(widget.file.storagePath);
      setState(() {
        _url = url;
        _isLoading = false;
      });
      
      if (kIsWeb && widget.file.extension?.toLowerCase() == 'pdf') {
        // Register the iframe for PDF
        // ignore: undefined_prefixed_name
        ui.platformViewRegistry.registerViewFactory(
          'pdf-viewer-${widget.file.id}',
          (int viewId) => html.IFrameElement()
            ..src = _url!
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%',
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extension = widget.file.extension?.toLowerCase();

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : Colors.grey[100],
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Lukk dokument',
        ),
        title: Text(widget.file.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () => launchUrl(Uri.parse(_url ?? '')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildContent(extension, isDark),
    );
  }

  Widget _buildContent(String? extension, bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Feil ved åpning av fil: $_error'));
    if (_url == null) return const Center(child: Text('Kunne ikke hente fil-URL'));

    switch (extension) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Center(
          child: InteractiveViewer(
            child: Image.network(
              _url!,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const CircularProgressIndicator();
              },
            ),
          ),
        );
      
      case 'pdf':
        if (kIsWeb) {
          return HtmlElementView(viewType: 'pdf-viewer-${widget.file.id}');
        } else {
          return const Center(child: Text('PDF-visning er foreløpig kun tilgjengelig i web-versjonen.\nBruk last ned-knappen for å se filen.'));
        }

      default:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              Text('Kan ikke vise forhåndsvisning for .${extension?.toUpperCase() ?? 'ukjent'}-filer.', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              const Text('Du kan fortsatt laste ned eller åpne filen i et annet program.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse(_url!)),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Last ned / Åpne fil'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        );
    }
  }
}
