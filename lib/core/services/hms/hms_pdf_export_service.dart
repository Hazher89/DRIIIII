import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Last ned / skriv ut HMS-PDF (web, mobil og desktop).
abstract final class HmsPdfExportService {
  static Future<void> download(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final safeName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: safeName,
    );
  }

  static Future<void> runWithFeedback(
    BuildContext context, {
    required Future<Uint8List> Function() generate,
    required String fileName,
  }) async {
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Genererer PDF…'),
                ],
              ),
            ),
          ),
        ),
      );
      final bytes = await generate();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await download(bytes, fileName: fileName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF klar: $fileName.pdf')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke lage PDF: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}
