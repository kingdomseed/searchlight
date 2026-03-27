// This is a CLI tool; print() is intentional output.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:searchlight/searchlight.dart';

const _defaultContentCap = 3000;

Future<void> main() async {
  await buildValidationAssets();
}

Future<void> buildValidationAssets({
  Directory? exampleRoot,
  int contentCap = _defaultContentCap,
}) async {
  final root = exampleRoot ?? _resolveExampleRoot(Directory.current.absolute);
  final localDir = Directory('${root.path}/.local');
  final sourceDir = Directory('${localDir.path}/source');
  final corpusFile = File('${localDir.path}/generated_search_corpus.json');
  final snapshotFile = File('${localDir.path}/generated_search_snapshot.json');

  if (!sourceDir.existsSync()) {
    throw FileSystemException(
      'Missing local source directory at ${sourceDir.path}',
    );
  }

  await localDir.create(recursive: true);
  final records = await _collectRecords(sourceDir, contentCap);

  final db = Searchlight.create(
    schema: Schema({
      'url': const TypedField(SchemaType.string),
      'title': const TypedField(SchemaType.string),
      'content': const TypedField(SchemaType.string),
      'type': const TypedField(SchemaType.enumType),
      'group': const TypedField(SchemaType.enumType),
    }),
  );

  try {
    records.forEach(db.insert);

    await corpusFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(records),
    );
    await snapshotFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(db.toJson()),
    );
  } finally {
    await db.dispose();
  }

  print(
    'Generated ${records.length} records: '
    '${corpusFile.path} and ${snapshotFile.path}',
  );
}

Future<List<Map<String, Object?>>> _collectRecords(
  Directory sourceDir,
  int contentCap,
) async {
  final markdownFiles = <File>[];
  await for (final entity in sourceDir.list(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
      markdownFiles.add(entity);
    }
  }
  markdownFiles.sort((a, b) => a.path.compareTo(b.path));

  final records = <Map<String, Object?>>[];
  for (final file in markdownFiles) {
    records.add(await _toRecord(file, sourceDir, contentCap));
  }
  return records;
}

Future<Map<String, Object?>> _toRecord(
  File file,
  Directory sourceDir,
  int contentCap,
) async {
  final raw = await file.readAsString();
  final normalizedSource = sourceDir.uri.path;
  final normalizedFile = file.uri.path;
  final start = normalizedSource.length +
      (normalizedSource.endsWith('/') ? 0 : 1);
  final relativePath = normalizedFile.substring(start);
  final relativeNoExt = relativePath.replaceFirst(RegExp(r'\.md$'), '');
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

Directory _resolveExampleRoot(Directory start) {
  var current = start;
  while (true) {
    final examplePubspec = File('${current.path}/pubspec.yaml');
    if (_isExamplePubspec(examplePubspec)) {
      return current;
    }

    final monorepoCandidate = Directory('${current.path}/packages/searchlight/example');
    final monorepoPubspec = File('${monorepoCandidate.path}/pubspec.yaml');
    if (_isExamplePubspec(monorepoPubspec)) {
      return monorepoCandidate;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      throw FileSystemException(
        'Could not resolve packages/searchlight/example root from ${start.path}',
      );
    }
    current = parent;
  }
}

bool _isExamplePubspec(File pubspec) {
  if (!pubspec.existsSync()) {
    return false;
  }
  final content = pubspec.readAsStringSync();
  return RegExp(
    r'^name:\s*searchlight_example\s*$',
    multiLine: true,
  ).hasMatch(content);
}

String? _segmentAfter(List<String> segments, int index) {
  final next = index + 1;
  if (next >= segments.length) {
    return null;
  }
  return segments[next];
}
