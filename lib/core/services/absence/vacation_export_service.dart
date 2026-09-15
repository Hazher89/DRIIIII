import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../utils/bytes_download.dart';
import '../../utils/norwegian_holidays.dart';
import 'vacation_year_matrix_model.dart';

/// Excel/PDF-eksport av ferieoversikt for et år.
abstract final class VacationExportService {
  static String _weekdayNb(int weekday) {
    const names = [
      '',
      'mandag',
      'tirsdag',
      'onsdag',
      'torsdag',
      'fredag',
      'lørdag',
      'søndag',
    ];
    return names[weekday.clamp(1, 7)];
  }

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

    final title = companyName?.trim().isNotEmpty == true
        ? 'Ferieoversikt $year - ${companyName!.trim()}'
        : 'Ferieoversikt $year';

    sheet.appendRow([TextCellValue(title)]);
    sheet.appendRow([
      TextCellValue(
        'Generert ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())} | '
        '${model.employeeRows.length} ansatte | '
        '${model.employeeRows.where((e) => e.totalWorkDays > 0).length} med ferie',
      ),
    ]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('Ansatt'),
      TextCellValue('Fra'),
      TextCellValue('Til'),
      TextCellValue('Periode'),
      TextCellValue('Virkedager'),
      TextCellValue('Status'),
      TextCellValue('Uker'),
    ]);

    for (final row in model.employeeRows) {
      if (row.spans.isEmpty) {
        sheet.appendRow([
          TextCellValue(row.name),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('Ingen ferie'),
          IntCellValue(0),
          TextCellValue('-'),
          TextCellValue(''),
        ]);
        continue;
      }
      for (final span in row.spans) {
        sheet.appendRow([
          TextCellValue(row.name),
          TextCellValue(DateFormat('dd.MM.yyyy').format(span.start)),
          TextCellValue(DateFormat('dd.MM.yyyy').format(span.end)),
          TextCellValue(span.periodLabel),
          IntCellValue(span.workDays),
          TextCellValue(span.statusLabel),
          TextCellValue(span.weekLabel),
        ]);
      }
      sheet.appendRow([
        TextCellValue('${row.name} (totalt)'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        IntCellValue(row.totalWorkDays),
        TextCellValue(''),
        TextCellValue(''),
      ]);
    }

    final holidays = excel['Røde dager $year'];
    holidays.appendRow([TextCellValue('Røde dager $year')]);
    holidays.appendRow([
      TextCellValue('Dato'),
      TextCellValue('Ukedag'),
      TextCellValue('Navn'),
    ]);
    for (final h in NorwegianHolidays.forYear(year)) {
      holidays.appendRow([
        TextCellValue(DateFormat('dd.MM.yyyy').format(h.date)),
        TextCellValue(_weekdayNb(h.date.weekday)),
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

    // Noto Sans støtter æ/ø/å og tankestreker (Helvetica gjør ikke).
    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();

    final title = companyName?.trim().isNotEmpty == true
        ? 'Ferieoversikt $year — ${companyName!.trim()}'
        : 'Ferieoversikt $year';

    final withVacation =
        model.employeeRows.where((e) => e.totalWorkDays > 0).length;

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

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(font: bold, fontSize: 16),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generert ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}  ·  '
              '${model.employeeRows.length} ansatte  ·  '
              '$withVacation med ferie  ·  '
              '${NorwegianHolidays.forYear(year).length} røde dager',
              style: pw.TextStyle(
                font: font,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (ctx) => [
          pw.Text(
            'Hvem har / har hatt ferie',
            style: pw.TextStyle(font: bold, fontSize: 11),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Ansatt',
              'Periode',
              'Virkedager',
              'Status',
              'Uker',
            ],
            data: tableData,
            headerStyle: pw.TextStyle(
              font: bold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B5E20)),
            cellStyle: pw.TextStyle(font: font, fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.2),
              1: const pw.FlexColumnWidth(3.2),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.4),
            },
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Røde dager $year',
            style: pw.TextStyle(font: bold, fontSize: 11),
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final h in NorwegianHolidays.forYear(year))
                pw.Text(
                  '${DateFormat('dd.MM').format(h.date)} ${h.name}',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 8,
                    color: PdfColors.red800,
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Tips: Hovedferie (18 dager) bør tas 1. juni–30. september. '
            'Virkedager teller ikke helg eller røde dager. '
            'Sjekk overlapping i avdelingen før godkjenning.',
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: PdfColors.grey700,
            ),
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
