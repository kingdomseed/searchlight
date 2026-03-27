import 'package:searchlight/searchlight.dart';
import 'package:searchlight_example/src/loaded_validation_source.dart';
import 'package:searchlight_example/src/search_result_item.dart';
import 'package:searchlight_example/src/validation_issue.dart';
import 'package:searchlight_example/src/validation_record.dart';

class SearchIndexService {
  const SearchIndexService();

  LoadedValidationSource buildFromRecords({
    required List<ValidationRecord> records,
    required String label,
    required int discoveredCount,
    List<ValidationIssue> issues = const [],
  }) {
    final db = Searchlight.create(
      schema: Schema({
        'pathLabel': const TypedField(SchemaType.string),
        'title': const TypedField(SchemaType.string),
        'content': const TypedField(SchemaType.string),
        'type': const TypedField(SchemaType.enumType),
        'group': const TypedField(SchemaType.enumType),
        'sourcePath': const TypedField(SchemaType.string),
        'displayBody': const TypedField(SchemaType.string),
      }),
    );

    final recordsById = <String, ValidationRecord>{};
    for (final record in records) {
      recordsById[record.pathLabel] = record;
      db.insert(record.toSearchDocument());
    }

    return LoadedValidationSource(
      db: db,
      records: List.unmodifiable(records),
      recordsById: Map.unmodifiable(recordsById),
      label: label,
      discoveredCount: discoveredCount,
      issues: List.unmodifiable(issues),
    );
  }

  LoadedValidationSource restoreFromSnapshot({
    required Map<String, Object?> json,
    required String label,
  }) {
    final rawDocuments = json['documents'];
    if (rawDocuments is! Map<String, dynamic>) {
      throw const FormatException(
        'Snapshot JSON must include a documents object.',
      );
    }

    final records = rawDocuments.values
        .map((dynamic entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException(
              'Snapshot contains a non-object document.',
            );
          }
          return ValidationRecord.fromMap(entry.cast<String, Object?>());
        })
        .toList(growable: false);

    return LoadedValidationSource(
      db: Searchlight.fromJson(json),
      records: records,
      recordsById: {for (final record in records) record.pathLabel: record},
      label: label,
      discoveredCount: records.length,
      issues: const [],
    );
  }

  List<SearchResultItem> browseAll(LoadedValidationSource source) {
    final sorted = [...source.records]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return sorted
        .map((record) => SearchResultItem(record: record, score: 0))
        .toList(growable: false);
  }

  List<SearchResultItem> search(LoadedValidationSource source, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return browseAll(source);
    }

    final result = source.db.search(
      term: trimmed,
      properties: const ['title', 'content'],
      limit: source.records.length,
    );

    return result.hits
        .map((hit) {
          final id =
              hit.document.tryGetString('pathLabel') ??
              hit.document.tryGetString('url') ??
              hit.document.getString('title');
          final record = source.recordsById[id]!;
          return SearchResultItem(record: record, score: hit.score);
        })
        .toList(growable: false);
  }
}
