import 'dart:convert';
import 'dart:io';

import 'package:searchlight/searchlight.dart';

final class BenchmarkSourceData {
  BenchmarkSourceData({
    required this.seedRecords,
    required this.includedSourceFiles,
    required this.skippedFilesByExtension,
    required this.sourceMode,
  });

  final List<Map<String, Object?>> seedRecords;
  final int includedSourceFiles;
  final Map<String, int> skippedFilesByExtension;
  final String sourceMode;
}

final _schema = Schema({
  'url': const TypedField(SchemaType.string),
  'title': const TypedField(SchemaType.string),
  'content': const TypedField(SchemaType.string),
  'type': const TypedField(SchemaType.enumType),
  'group': const TypedField(SchemaType.enumType),
});
const _defaultContentCap = 3000;

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(
    value >= 10 || unitIndex == 0 ? 0 : 1,
  )} ${units[unitIndex]}';
}

int _rss() => ProcessInfo.currentRss;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    if (args.isEmpty) {
      exitCode = 64;
    }
    return;
  }

  final sourcePath = args.first;
  final repeatCount = args.length > 1 ? int.parse(args[1]) : 1;
  final contentCap =
      args.length > 2 ? int.parse(args[2]) : _defaultContentCap;
  final sourceData = await _loadSeedRecords(sourcePath, contentCap: contentCap);

  final rssAfterSeedLoad = _rss();
  final db = Searchlight.create(schema: _schema);
  final rssAfterDbCreate = _rss();

  final insertWatch = Stopwatch()..start();
  final docsInserted = _insertSeedRecords(
    db,
    sourceData.seedRecords,
    repeatCount: repeatCount,
  );
  insertWatch.stop();

  sourceData.seedRecords.clear();

  final wholeProcessRssAfterInsert = _rss();
  final rssDeltaFromSeedLoad =
      wholeProcessRssAfterInsert - rssAfterSeedLoad;
  final jsonMap = db.toJson();
  final jsonString = jsonEncode(jsonMap);
  final cborBytes = db.serialize();
  final peakWholeProcessRssAfterSerialize = _rss();

  final restoreWatch = Stopwatch()..start();
  final restored = Searchlight.deserialize(cborBytes);
  restoreWatch.stop();
  final peakWholeProcessRssAfterRestore = _rss();
  final skippedSourceFiles = sourceData.skippedFilesByExtension.values.fold(
    0,
    (sum, count) => sum + count,
  );
  final datasetMode = repeatCount > 1
      ? 'repeated-seed-clones'
      : sourceData.sourceMode;

  stdout
    ..writeln('docs=$docsInserted')
    ..writeln('seed_docs=${sourceData.includedSourceFiles}')
    ..writeln('repeat_count=$repeatCount')
    ..writeln('dataset_mode=$datasetMode')
    ..writeln('content_cap=$contentCap')
    ..writeln('supported_extensions=.md,.markdown,.txt')
    ..writeln('included_source_files=${sourceData.includedSourceFiles}')
    ..writeln('skipped_source_files=$skippedSourceFiles')
    ..writeln(
      'skipped_by_extension=${jsonEncode(sourceData.skippedFilesByExtension)}',
    )
    ..writeln(
      'whole_process_rss_after_seed_load=${_formatBytes(rssAfterSeedLoad)}',
    )
    ..writeln(
      'whole_process_rss_after_db_create=${_formatBytes(rssAfterDbCreate)}',
    )
    ..writeln(
      'whole_process_rss_after_insert='
      '${_formatBytes(wholeProcessRssAfterInsert)}',
    )
    ..writeln(
      'rss_delta_seed_load_to_insert=${_formatBytes(rssDeltaFromSeedLoad)}',
    )
    ..writeln(
      'peak_whole_process_rss_after_serialize='
      '${_formatBytes(peakWholeProcessRssAfterSerialize)}',
    )
    ..writeln(
      'peak_whole_process_rss_after_restore='
      '${_formatBytes(peakWholeProcessRssAfterRestore)}',
    )
    ..writeln(
      'json_snapshot=${_formatBytes(utf8.encode(jsonString).length)}',
    )
    ..writeln('cbor_snapshot=${_formatBytes(cborBytes.length)}')
    ..writeln('insert_ms=${insertWatch.elapsedMilliseconds}')
    ..writeln('restore_ms=${restoreWatch.elapsedMilliseconds}')
    ..writeln(
      'measurement_note=RSS is approximate whole-process memory, '
      'not isolated index memory.',
    )
    ..writeln(
      'scaling_note=repeated-seed-clones reuses most vocabulary and '
      'understates unique-corpus growth.',
    )
    ..writeln('count=${db.count}')
    ..writeln('restored_count=${restored.count}');

  await db.dispose();
  await restored.dispose();
}

Future<BenchmarkSourceData> _loadSeedRecords(
  String sourcePath, {
  required int contentCap,
}) async {
  final sourceFile = File(sourcePath);
  if (sourceFile.existsSync()) {
    if (_extensionForPath(sourcePath) != 'json') {
      throw FileSystemException(
        'File source must be a JSON corpus file',
        sourcePath,
      );
    }

    final raw = await sourceFile.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FileSystemException(
        'JSON corpus must decode to a top-level list',
        sourcePath,
      );
    }
    final seedRecords = decoded.cast<Map<String, Object?>>();
    return BenchmarkSourceData(
      seedRecords: seedRecords,
      includedSourceFiles: seedRecords.length,
      skippedFilesByExtension: const {},
      sourceMode: 'json-corpus-file',
    );
  }

  final sourceDir = Directory(sourcePath);
  if (!sourceDir.existsSync()) {
    throw FileSystemException('Source directory does not exist', sourcePath);
  }

  final markdownFiles = <File>[];
  final skippedFilesByExtension = <String, int>{};
  await for (final entity in sourceDir.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }

    if (_isSupportedTextPath(entity.path)) {
      markdownFiles.add(entity);
      continue;
    }

    final extension = _extensionForPath(entity.path);
    skippedFilesByExtension[extension] =
        (skippedFilesByExtension[extension] ?? 0) + 1;
  }
  markdownFiles.sort((a, b) => a.path.compareTo(b.path));

  final seedRecords = <Map<String, Object?>>[];
  for (final file in markdownFiles) {
    seedRecords.add(await _toRecord(file, sourceDir, contentCap));
  }
  return BenchmarkSourceData(
    seedRecords: seedRecords,
    includedSourceFiles: seedRecords.length,
    skippedFilesByExtension: skippedFilesByExtension,
    sourceMode: 'directory-text-files',
  );
}

int _insertSeedRecords(
  Searchlight db,
  List<Map<String, Object?>> seedRecords, {
  required int repeatCount,
}) {
  var inserted = 0;

  if (repeatCount <= 1) {
    seedRecords.forEach(db.insert);
    return seedRecords.length;
  }

  for (var i = 0; i < repeatCount; i++) {
    for (final record in seedRecords) {
      db.insert({
        'id': '${record['url']}#$i',
        'url': '${record['url']}#$i',
        'title': '${record['title']} $i',
        'content': '${record['content']} variant $i',
        'type': record['type'],
        'group': record['group'],
      });
      inserted++;
    }
  }

  return inserted;
}

Future<Map<String, Object?>> _toRecord(
  File file,
  Directory sourceDir,
  int contentCap,
) async {
  final raw = await file.readAsString();
  final normalizedSource = sourceDir.uri.path;
  final normalizedFile = file.uri.path;
  final start =
      normalizedSource.length + (normalizedSource.endsWith('/') ? 0 : 1);
  final relativePath = normalizedFile.substring(start);
  final relativeNoExt = relativePath.replaceFirst(
    RegExp(r'\.(md|markdown|txt)$', caseSensitive: false),
    '',
  );
  final segments = relativeNoExt.split('/');

  final title = _extractTitle(raw, segments.last);
  final typeAndGroup = _deriveTypeAndGroup(segments);
  final normalized = _stripLeadingH1(raw);
  final content = normalized.length > contentCap
      ? normalized.substring(0, contentCap)
      : normalized;

  return <String, Object?>{
    'url': '/$relativeNoExt',
    'title': title,
    'content': content,
    'type': typeAndGroup.$1,
    'group': typeAndGroup.$2,
  };
}

String _extractTitle(String raw, String fallbackSlug) {
  final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(raw);
  if (match != null) {
    return match.group(1)!.trim();
  }

  final words = fallbackSlug
      .split(RegExp('[-_]'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
  return words.join(' ');
}

(String, String) _deriveTypeAndGroup(List<String> segments) {
  final idxSpells = segments.indexOf('spells');
  if (idxSpells != -1) {
    final group = _segmentAfter(segments, idxSpells) ?? 'general';
    return ('spell', group);
  }

  final idxBestiary = segments.indexOf('bestiary');
  if (idxBestiary != -1) {
    final group = _segmentAfter(segments, idxBestiary) ?? 'general';
    return ('monster', group);
  }

  final idxCreatures = segments.indexOf('creatures');
  if (idxCreatures != -1) {
    final group = _segmentAfter(segments, idxCreatures) ?? 'general';
    return ('monster', group);
  }

  if (segments.contains('rules')) {
    return ('rule', 'general');
  }

  if (segments.contains('items') || segments.contains('equipment')) {
    return ('item', 'general');
  }

  if (segments.contains('glossary')) {
    return ('glossary', 'general');
  }

  return ('reference', 'general');
}

String _stripLeadingH1(String raw) {
  final lines = raw.split('\n');
  if (lines.isEmpty) {
    return raw;
  }

  if (!lines.first.trimLeft().startsWith('# ')) {
    return raw;
  }

  var idx = 1;
  while (idx < lines.length && lines[idx].trim().isEmpty) {
    idx++;
  }
  return lines.sublist(idx).join('\n');
}

bool _isSupportedTextPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') ||
      lower.endsWith('.markdown') ||
      lower.endsWith('.txt');
}

String _extensionForPath(String path) {
  final fileName = path.split(Platform.pathSeparator).last.toLowerCase();
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) {
    return '<none>';
  }
  return fileName.substring(dotIndex + 1);
}

const _usage = '''
Usage: dart run tool/memory_benchmark.dart <source-path> [repeat-count] [content-cap]

Arguments:
  <source-path>   Required. Either:
                  - a directory containing .md/.markdown/.txt files, or
                  - a JSON corpus file containing a top-level array of records
  [repeat-count]  Optional. Defaults to 1.
  [content-cap]   Optional. Defaults to 3000 characters per record.

Notes:
  - RSS values are whole-process measurements, not isolated index memory.
  - Repeat counts above 1 use repeated seed clones and understate unique-corpus growth.
''';

String? _segmentAfter(List<String> segments, int index) {
  final next = index + 1;
  if (next >= segments.length) {
    return null;
  }
  return segments[next];
}
