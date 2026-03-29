/// A full-text search engine for Dart.
library;

export 'src/core/database.dart' show Searchlight;
export 'src/core/doc_id.dart';
export 'src/core/document.dart';
export 'src/core/exceptions.dart';
export 'src/core/schema.dart';
export 'src/core/search_algorithm.dart';
export 'src/core/types.dart';
export 'src/extensions/components.dart';
export 'src/extensions/hooks.dart';
export 'src/extensions/plugin.dart';
export 'src/highlight/highlighter.dart';
export 'src/highlight/positions.dart';
export 'src/indexing/index_manager.dart' show SearchIndex;
export 'src/indexing/sort_index.dart' show SortIndex;
export 'src/persistence/format.dart'
    show PersistenceFormat, currentFormatVersion;
export 'src/persistence/storage.dart';
export 'src/search/filters.dart';
export 'src/storage/documents_store.dart';
export 'src/text/stop_words.dart';
export 'src/text/tokenizer.dart';
