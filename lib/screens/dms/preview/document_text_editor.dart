import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

/// Redigerbar tekst (Word-uttrekk, TXT, CSV som tekst).
class DocumentTextEditor extends StatefulWidget {
  final Uint8List bytes;
  final String? extension;
  final ValueChanged<String>? onChanged;

  const DocumentTextEditor({
    super.key,
    required this.bytes,
    this.extension,
    this.onChanged,
  });

  @override
  State<DocumentTextEditor> createState() => DocumentTextEditorState();
}

class DocumentTextEditorState extends State<DocumentTextEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _loadText());
    _controller.addListener(() => widget.onChanged?.call(_controller.text));
  }

  String _loadText() {
    final ext = widget.extension?.toLowerCase();
    if (ext == 'docx') {
      try {
        final archive = ZipDecoder().decodeBytes(widget.bytes);
        for (final f in archive.files) {
          if (f.name == 'word/document.xml') {
            return _stripXml(utf8.decode(f.content as List<int>));
          }
        }
      } catch (_) {}
    }
    return utf8.decode(widget.bytes, allowMalformed: true);
  }

  String get text => _controller.text;

  Uint8List exportBytes({bool asDocx = false}) {
    if (asDocx) {
      return _buildSimpleDocx(_controller.text);
    }
    return Uint8List.fromList(utf8.encode(_controller.text));
  }

  Uint8List _buildSimpleDocx(String text) {
    final paragraphs = text.split('\n');
    final body = paragraphs
        .map(
          (p) =>
              '<w:p><w:r><w:t xml:space="preserve">${_escapeXml(p)}</w:t></w:r></w:p>',
        )
        .join();
    final documentXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body</w:body></w:document>';

    final archive = Archive();
    archive.addFile(ArchiveFile('[Content_Types].xml', 0, utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>',
    )));
    archive.addFile(ArchiveFile('word/document.xml', 0, utf8.encode(documentXml)));
    archive.addFile(ArchiveFile('_rels/.rels', 0, utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>',
    )));
    final zipped = ZipEncoder().encode(archive)!;
    return Uint8List.fromList(zipped);
  }

  String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF2B579A),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(
            children: [
              Icon(Icons.description, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Dokument – rediger tekst',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Skriv her…',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _stripXml(String xml) {
  return xml
      .replaceAll(RegExp(r'<w:tab[^>]*/>', caseSensitive: false), '\t')
      .replaceAll(RegExp(r'</w:p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'&nbsp;'), ' ')
      .replaceAll(RegExp(r'&amp;'), '&')
      .replaceAll(RegExp(r'&lt;'), '<')
      .replaceAll(RegExp(r'&gt;'), '>')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
      .trim();
}
