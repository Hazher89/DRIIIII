/// Gjør HMS- og arbeidsdokumenter om til avsnitt, overskrifter og punkter.
abstract final class HmsProse {
  static String format(String raw) {
    final cleaned = _unwrap(raw);
    if (cleaned.isEmpty) return '';

    final blocks = <_Block>[];
    final rules = <String>[];
    final prose = <String>[];

    void flushProse() {
      if (prose.isEmpty) return;
      blocks.add(_Block.paragraph(prose.join(' ')));
      prose.clear();
    }

    void flushRules() {
      if (rules.isEmpty) return;
      if (rules.length == 1) {
        prose.add(rules.first);
      } else {
        flushProse();
        blocks.add(_Block.bullets(List.of(rules)));
      }
      rules.clear();
    }

    for (final line in cleaned) {
      if (_isHeading(line)) {
        flushRules();
        flushProse();
        blocks.add(_Block.heading(line.replaceFirst(RegExp(r':$'), '')));
        continue;
      }
      if (_isBullet(line)) {
        flushProse();
        rules.add(_stripBullet(line));
        continue;
      }
      if (_isRule(line)) {
        flushProse();
        rules.add(line);
        continue;
      }
      flushRules();
      prose.add(line);
    }
    flushRules();
    flushProse();

    final out = StringBuffer();
    for (final block in blocks) {
      if (out.isNotEmpty) out.writeln();
      switch (block.kind) {
        case _Kind.heading:
          out.writeln(block.lines.first);
        case _Kind.paragraph:
          out.writeln(block.lines.first);
        case _Kind.bullets:
          for (final line in block.lines) {
            out.writeln('• $line');
          }
      }
    }
    return out.toString().trim();
  }

  static List<String> _unwrap(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .toList();

    final out = <String>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.toLowerCase().startsWith('kilde:')) continue;
      if (out.isNotEmpty && out.last == line) continue;
      if (out.isNotEmpty &&
          out.last.endsWith('-') &&
          !out.last.endsWith(' -') &&
          line.isNotEmpty) {
        out[out.length - 1] =
            '${out.last.substring(0, out.last.length - 1)}$line';
        continue;
      }
      if (out.isNotEmpty &&
          !_endsSentence(out.last) &&
          !out.last.endsWith(':') &&
          !_isBullet(out.last) &&
          RegExp(r'^[a-zæøå0-9(]').hasMatch(line)) {
        out[out.length - 1] = '${out.last} $line';
        continue;
      }
      out.add(line);
    }

    if (out.length >= 2 && out[0] == out[1]) out.removeAt(0);
    return out;
  }

  static bool _endsSentence(String line) =>
      line.endsWith('.') ||
      line.endsWith('!') ||
      line.endsWith('?') ||
      line.endsWith(':');

  static bool _isBullet(String line) =>
      line.startsWith('•') ||
      line.startsWith('- ') ||
      line.startsWith('* ') ||
      RegExp(r'^\d+[.)]\s').hasMatch(line);

  static String _stripBullet(String line) => line
      .replaceFirst(RegExp(r'^[•\-*]\s*'), '')
      .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
      .trim();

  static bool _isHeading(String line) {
    if (line.length > 72 || line.length < 3) return false;
    if (_isBullet(line)) return false;
    if (RegExp(r'^(ja|nei)\b', caseSensitive: false).hasMatch(line)) {
      return false;
    }
    if (line.endsWith('.') || line.endsWith('!') || line.endsWith('?')) {
      return false;
    }
    if (line.endsWith(':')) return line.length <= 60;
    final letters = line.replaceAll(RegExp(r'[^A-Za-zÆØÅæøå]'), '');
    if (letters.length >= 4 && line == line.toUpperCase()) return true;
    return line.length <= 42 && !line.contains(',') && !line.contains(';');
  }

  static bool _isRule(String line) {
    if (line.length > 140 || line.length < 8) return false;
    if (!_endsSentence(line) || line.endsWith(':') || line.endsWith('?')) {
      return false;
    }
    final words = line.split(RegExp(r'\s+'));
    return words.length <= 22;
  }
}

enum _Kind { heading, paragraph, bullets }

class _Block {
  const _Block(this.kind, this.lines);
  final _Kind kind;
  final List<String> lines;

  factory _Block.heading(String text) => _Block(_Kind.heading, [text]);
  factory _Block.paragraph(String text) => _Block(_Kind.paragraph, [text]);
  factory _Block.bullets(List<String> lines) => _Block(_Kind.bullets, lines);
}
