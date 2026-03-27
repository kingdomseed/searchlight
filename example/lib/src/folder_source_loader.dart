import 'package:searchlight_example/src/validation_issue.dart';
import 'package:searchlight_example/src/validation_record.dart';

import 'folder_source_loader_impl_stub.dart'
    if (dart.library.io) 'folder_source_loader_impl_io.dart'
    as impl;

final class FolderLoadResult {
  const FolderLoadResult({
    required this.rootPath,
    required this.discoveredMarkdownFiles,
    required this.records,
    required this.issues,
  });

  final String rootPath;
  final int discoveredMarkdownFiles;
  final List<ValidationRecord> records;
  final List<ValidationIssue> issues;
}

abstract class FolderSourceLoader {
  Future<FolderLoadResult> load(String rootPath);
}

FolderSourceLoader createFolderSourceLoader() {
  return impl.createFolderSourceLoader();
}
