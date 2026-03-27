final class ValidationRecord {
  const ValidationRecord({
    required this.id,
    required this.title,
    required this.content,
    required this.displayBody,
    required this.pathLabel,
    required this.group,
    required this.type,
    this.sourcePath,
  });

  final String id;
  final String title;
  final String content;
  final String displayBody;
  final String pathLabel;
  final String group;
  final String type;
  final String? sourcePath;

  factory ValidationRecord.fromMap(Map<String, Object?> map) {
    final pathLabel =
        _stringAt(map, 'pathLabel') ??
        _stringAt(map, 'relativePath') ??
        _stringAt(map, 'url') ??
        '';
    final title = _stringAt(map, 'title') ?? 'Untitled';
    final content = _stringAt(map, 'content') ?? '';

    return ValidationRecord(
      id:
          _stringAt(map, 'id') ??
          _stringAt(map, 'relativePath') ??
          _stringAt(map, 'url') ??
          title,
      title: title,
      content: content,
      displayBody: _stringAt(map, 'displayBody') ?? content,
      pathLabel: pathLabel,
      group: _stringAt(map, 'group') ?? 'general',
      type: _stringAt(map, 'type') ?? 'record',
      sourcePath: _stringAt(map, 'sourcePath'),
    );
  }

  Map<String, Object?> toSearchDocument() {
    return <String, Object?>{
      'title': title,
      'content': content,
      'pathLabel': pathLabel,
      'group': group,
      'type': type,
      'sourcePath': sourcePath ?? '',
      'displayBody': displayBody,
    };
  }

  static String? _stringAt(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }
}
