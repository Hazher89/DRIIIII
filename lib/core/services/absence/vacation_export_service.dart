import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../utils/bytes_download.dart';
import '../../utils/norwegian_holidays.dart';
import 'vacation_year_matrix_model.dart';

/// Excel/PDF-eksport av ferieoversikt for et år.
abstract final class VacationExportService {
  static Future<void> exportExcel({
    required int year,
    required List<UserProfile> employees,
    required List<Absence> vacations,
    String? companyName,
  }) async {
    final model = VacationYearMatrixModel.build(
      year: year,
      employees: employees,
      vacations: vacations,
    );
    final excel = Excel.createExcel();
    final sheet = excel['Ferie $year'];
    try {
      excel.delete('Sheet1');
    } catch (_) {}

    sheet.appendRow([
      TextCellValue(companyName?.trim().isNotEmpty == true
          ? 'Ferieoversikt $year — ${companyName!.trim()}'
          : 'Ferieoversikt $year'),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Generert ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
      ),
    ]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('Ansatt'),
      TextCellValue('Periode'),
      TextCellValue('Virkedager'),
      TextCellValue('Status'),
      TextCellValue('Uker'),
    ]);

    for (final row in model.employeeRows) {
      if (row.spans.isEmpty) {
        sheet.appendRow([
          TextCellValue(row.name),
          TextCellValue('—'),
          IntCellValue(0),
          TextCellValue('Ingen ferie'),
          TextCellValue(''),
        ]);
        continue;
      }
      for (final span in row.spans) {
        sheet.appendRow([
          TextCellValue(row.name),
          TextCellValue(span.periodLabel),
          IntCellValue(span.workDays),
          TextCellValue(span.statusLabel),
          TextCellValue(span.weekLabel),
        ]);
      }
      sheet.appendRow([
        TextCellValue('${row.name} — totalt'),
        TextCellValue(''),
        IntCellValue(row.totalWorkDays),
        TextCellValue(''),
        TextCellValue(''),
      ]);
    }

    final holidays = excel['Røde dager $year'];
    holidays.appendRow([TextCellValue('Røde dager $year')]);
    holidays.appendRow([TextCellValue('Dato'), TextCellValue('Navn')]);
    for (final h in NorwegianHolidays.forYear(year)) {
      holidays.appendRow([
        TextCellValue(DateFormat('dd.MM.yyyy').format(h.date)),
        TextCellValue(h.name),
      ]);
    }

    final weeks = excel['Ukematrise $year'];
    weeks.appendRow([
      TextCellValue('Ansatt'),
      ...model.weeks.map((w) => TextCellValue('U${w.week}')),
      TextCellValue('Totalt'),
    ]);
    for (final row in model.employeeRows) {
      weeks.appendRow([
        TextCellValue(row.name),
        ...model.weeks.map((w) {
          final d = row.daysInWeek[w.week] ?? 0;
          return d > 0 ? IntCellValue(d) : TextCellValue('');
        }),
        IntCellValue(row.totalWorkDays),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Kunne ikke lage Excel-fil');
    }
    await downloadBytes(
      Uint8List.fromList(bytes),
      'ferieoversikt_$year.xlsx',
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  static Future<void> exportPdf({
    required int year,
    required List<UserProfile> employees,
    required List<Absence> vacations,
    String? companyName,
  }) async {
    final model = VacationYearMatrixModel.build(
      year: year,
      employees: employees,
      vacations: vacations,
    );
    final doc = pw.Document();
    final title = companyName?.trim().isNotEmpty == true
        ? 'Ferieoversikt $year — ${companyName!.trim()}'
        : 'Ferieoversikt $year';

    final tableData = <List<String>>[];
    for (final row in model.employeeRows) {
      if (row.spans.isEmpty) {
        tableData.add([row.name, 'Ingen ferie', '0', '—', '']);
      } else {
        for (final span in row.spans) {
          tableData.add([
            row.name,
            span.periodLabel,
            '${span.workDays}',
            span.statusLabel,
            span.weekLabel,
          ]);
        }
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generert ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())} · '
              '${model.employeeRows.length} ansatte · '
              '${NorwegianHolidays.forYear(year).length} røde dager',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        build: (ctx) => [
          pw.Text(
            'Hvem har / har hatt ferie',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Ansatt', 'Periode', 'Dager', 'Status', 'Uker'],
            data: tableData,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Røde dager $year',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final h in NorwegianHolidays.forYear(year))
                pw.Text(
                  '${DateFormat('dd.MM').format(h.date)} ${h.name}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Tips: Hovedferie (18 dager) bør tas 1. juni–30. september. '
            'Virkedager teller ikke helg eller røde dager. '
            'Sjekk overlapping i avdelingen før godkjenning.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await downloadBytes(
      Uint8List.fromList(bytes),
      'ferieoversikt_$year.pdf',
      mime: 'application/pdf',
    );
  }
}
