import 'package:searchlight_example/src/folder_source_loader.dart';

FolderSourceLoader createFolderSourceLoader() =>
    _UnsupportedFolderSourceLoader();

final class _UnsupportedFolderSourceLoader implements FolderSourceLoader {
  @override
  Future<FolderLoadResult> load(String rootPath) {
    throw UnsupportedError(
      'Desktop folder loading is not supported on this platform.',
    );
  }
}
