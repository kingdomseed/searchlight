import 'package:searchlight/searchlight.dart';
import 'package:searchlight_example/src/validation_issue.dart';
import 'package:searchlight_example/src/validation_record.dart';

final class LoadedValidationSource {
  const LoadedValidationSource({
    required this.db,
    required this.records,
    required this.recordsById,
    required this.label,
    required this.discoveredCount,
    required this.issues,
  });

  final Searchlight db;
  final List<ValidationRecord> records;
  final Map<String, ValidationRecord> recordsById;
  final String label;
  final int discoveredCount;
  final List<ValidationIssue> issues;

  int get indexedCount => records.length;

  Future<void> dispose() => db.dispose();
}
