import 'dart:io';

import 'package:searchlight_example/src/folder_source_loader.dart';
import 'package:searchlight_example/src/markdown_record_extractor.dart';
import 'package:searchlight_example/src/validation_issue.dart';
import 'package:searchlight_example/src/validation_record.dart';

FolderSourceLoader createFolderSourceLoader() => _IoFolderSourceLoader();

final class _IoFolderSourceLoader implements FolderSourceLoader {
  _IoFolderSourceLoader() : _extractor = const MarkdownRecordExtractor();

  final MarkdownRecordExtractor _extractor;

  @override
  Future<FolderLoadResult> load(String rootPath) async {
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      throw FileSystemException('Selected folder does not exist.', rootPath);
    }

    final markdownFiles = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        markdownFiles.add(entity);
      }
    }
    markdownFiles.sort((a, b) => a.path.compareTo(b.path));

    final issues = <ValidationIssue>[];
    final records = <ValidationRecord>[];
    final seenIds = <String>{};

    for (final file in markdownFiles) {
      try {
        final raw = await file.readAsString();
        final record = _extractor.extract(
          filePath: file.path,
          rootPath: root.path,
          raw: raw,
        );
        if (!seenIds.add(record.id)) {
          issues.add(
            ValidationIssue(
              path: file.path,
              message: 'Duplicate derived id "${record.id}".',
            ),
          );
          continue;
        }
        records.add(record);
      } on Object catch (error) {
        issues.add(ValidationIssue(path: file.path, message: error.toString()));
      }
    }

    return FolderLoadResult(
      rootPath: root.path,
      discoveredMarkdownFiles: markdownFiles.length,
      records: records,
      issues: issues,
    );
  }
}
