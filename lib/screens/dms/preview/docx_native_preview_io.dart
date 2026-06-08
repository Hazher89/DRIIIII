import 'dart:io';

import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:path_provider/path_provider.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

Widget buildDocxNativePreview(Uint8List bytes) {
  return _DocxNativePreview(bytes: bytes);
}

class _DocxNativePreview extends StatefulWidget {
  final Uint8List bytes;

  const _DocxNativePreview({required this.bytes});

  @override
  State<_DocxNativePreview> createState() => _DocxNativePreviewState();
}

class _DocxNativePreviewState extends State<_DocxNativePreview> {
  late final Future<List<Widget>> _layoutFuture;

  @override
  void initState() {
    super.initState();
    _layoutFuture = _render();
  }

  Future<List<Widget>> _render() async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/dms_preview_${DateTime.now().millisecondsSinceEpoch}.docx',
    );
    await file.writeAsBytes(widget.bytes, flush: true);
    return DocxExtractor().renderLayout(file);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Widget>>(
      future: _layoutFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const DriftProLoadingCenter();
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Kunne ikke vise dokumentet lokalt.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final widgets = snapshot.data ?? const <Widget>[];
        if (widgets.isEmpty) {
          return const Center(child: Text('Tomt dokument'));
        }
        return ColoredBox(
          color: Colors.white,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: widgets,
            ),
          ),
        );
      },
    );
  }
}
