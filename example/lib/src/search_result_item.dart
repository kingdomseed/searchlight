import 'package:searchlight_example/src/validation_record.dart';

final class SearchResultItem {
  const SearchResultItem({required this.record, required this.score});

  final ValidationRecord record;
  final double score;
}
