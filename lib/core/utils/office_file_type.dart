enum OfficeFileType { excel, word, powerpoint, csv, unknown }

class OfficeFileTypeHelper {
  OfficeFileTypeHelper._();

  static OfficeFileType fromExtension(String? ext) {
    if (ext == null) return OfficeFileType.unknown;
    switch (ext) {
      case 'xlsx':
      case 'xlsm':
      case 'xls':
        return OfficeFileType.excel;
      case 'csv':
        return OfficeFileType.csv;
      case 'docx':
      case 'doc':
      case 'odt':
      case 'rtf':
        return OfficeFileType.word;
      case 'pptx':
      case 'ppt':
      case 'odp':
        return OfficeFileType.powerpoint;
      default:
        return OfficeFileType.unknown;
    }
  }
}
