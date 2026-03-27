import 'package:path/path.dart' as p;
import 'package:searchlight_example/src/validation_record.dart';

class MarkdownRecordExtractor {
  const MarkdownRecordExtractor();

  ValidationRecord extract({
    required String filePath,
    required String rootPath,
    required String raw,
  }) {
    final relativePath = p.posix.normalize(
      p.relative(filePath, from: rootPath).replaceAll(r'\', '/'),
    );
    final title = _extractTitle(raw, p.basenameWithoutExtension(filePath));
    final markdown = raw.trim();
    final content = _stripLeadingH1(markdown);

    return ValidationRecord(
      id: relativePath,
      title: title,
      content: content,
      displayBody: markdown,
      pathLabel: relativePath,
      group: _groupFor(relativePath),
      type: _typeFor(relativePath),
      sourcePath: filePath,
    );
  }

  String _extractTitle(String raw, String fallbackFileName) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(raw);
    if (match != null) {
      return match.group(1)!.trim();
    }

    final words = fallbackFileName
        .split(RegExp('[-_]'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
    return words.join(' ');
  }

  String _stripLeadingH1(String markdown) {
    final lines = markdown.split('\n');
    if (lines.isEmpty || !lines.first.trimLeft().startsWith('# ')) {
      return markdown;
    }

    var index = 1;
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    return lines.sublist(index).join('\n').trim();
  }

  String _groupFor(String relativePath) {
    final segments = p.posix.split(relativePath);
    return segments.isEmpty ? 'root' : segments.first;
  }

  String _typeFor(String relativePath) {
    final normalized = relativePath.toLowerCase();
    if (normalized.contains('/spells') || normalized.startsWith('spells/')) {
      return 'spell';
    }
    if (normalized.contains('/creatures') || normalized.contains('/monsters')) {
      return 'monster';
    }
    if (normalized.contains('/rules') || normalized.contains('/system/')) {
      return 'rule';
    }
    return 'reference';
  }
}
