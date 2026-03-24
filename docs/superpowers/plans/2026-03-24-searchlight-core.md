# Searchlight Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `searchlight` core Dart package — a full-text search engine with BM25/QPS/PT15 scoring, filtering, facets, geosearch, highlighting, and persistence.

**Architecture:** Pure Dart package with zero Flutter dependencies. In-memory inverted index backed by HashMap, type-safe schema and document wrappers via sealed classes, pluggable scoring algorithms, and optional CBOR/JSON persistence with format versioning.

**Tech Stack:** Dart 3.3+, `very_good_analysis` (^10.0.0), `unorm_dart`, `snowball_stemmer`, `r_tree`, `geobase`, `cbor`

**Conventions:**
- Use `final class` for all concrete classes that should not be subclassed
- Use `abstract sealed class` for base types with exhaustive subtypes
- Use `Map<String, Object?>` (not `dynamic`) throughout serialization APIs
- Tests import from `src/` directly (not barrel) during incremental development
- Empty-term search (`term: ''`) returns all documents (enables filter-only queries)
- `properties` parameter defaults to all string fields in the schema when omitted

**Spec:** `docs/superpowers/specs/2026-03-24-searchlight-design.md`

**Research:** `docs/research/dart-ecosystem-findings.md`

---

## File Structure

```
packages/searchlight/
├── lib/
│   ├── searchlight.dart                    # Barrel file — public API exports
│   └── src/
│       ├── core/
│       │   ├── database.dart               # Searchlight class — create, CRUD, search, lifecycle
│       │   ├── schema.dart                 # SchemaType enum, SchemaField sealed hierarchy, Schema class
│       │   ├── doc_id.dart                 # DocId extension type (extracted for early availability)
│       │   ├── document.dart               # Document wrapper with typed accessors
│       │   ├── document_adapter.dart       # DocumentAdapter<T> abstract interface
│       │   ├── types.dart                  # SearchResult, SearchHit, FacetValue, GeoPoint, SortBy, etc.
│       │   └── exceptions.dart             # SearchlightException sealed hierarchy
│       ├── indexing/
│       │   ├── index_manager.dart          # Orchestrates per-field index creation/updates
│       │   ├── inverted_index.dart         # HashMap<String, PostingList> for string fields
│       │   ├── posting_list.dart           # Per-term doc refs, frequencies, positions
│       │   ├── radix_tree.dart             # Prefix tree for autocomplete
│       │   ├── facet_index.dart            # Enum counting/aggregation
│       │   ├── numeric_index.dart          # SplayTreeMap for range queries
│       │   ├── boolean_index.dart          # Bitset for true/false filtering
│       │   ├── geo_index.dart              # Geohash + R-tree spatial index
│       │   └── sort_index.dart             # Pre-sorted field indexes
│       ├── scoring/
│       │   ├── scorer.dart                 # Sealed Scorer hierarchy + factory
│       │   ├── bm25.dart                   # Bm25Scorer
│       │   ├── qps.dart                    # QpsScorer
│       │   └── pt15.dart                   # Pt15Scorer
│       ├── text/
│       │   ├── pipeline.dart               # TokenPipeline — composable transforms
│       │   ├── tokenizer.dart              # Unicode-aware splitting
│       │   ├── normalizer.dart             # NFC normalization
│       │   ├── stemmer.dart                # Language-aware stemming wrapper
│       │   ├── stop_words.dart             # Per-language stop word sets
│       │   └── fuzzy.dart                  # Levenshtein edit distance
│       ├── search/
│       │   ├── engine.dart                 # Query execution — scoring, filtering, ranking
│       │   ├── filters.dart                # Filter sealed hierarchy + helpers
│       │   ├── facets.dart                 # Facet aggregation
│       │   ├── grouping.dart               # Result grouping
│       │   └── boost.dart                  # Field boosting
│       ├── highlight/
│       │   ├── highlighter.dart            # Highlighter class (standalone + pipeline-aware)
│       │   └── positions.dart              # HighlightPosition, HighlightResult, trim
│       ├── persistence/
│       │   ├── format.dart                 # Format version constant, header structure
│       │   ├── json_serializer.dart        # JSON serialization
│       │   ├── cbor_serializer.dart        # CBOR serialization
│       │   └── storage.dart                # SearchlightStorage interface + FileStorage
│       └── isolate/
│           ├── worker.dart                 # Isolate index builder
│           └── transfer.dart               # TransferableTypedData helpers
├── test/
│   ├── core/
│   │   ├── schema_test.dart
│   │   ├── document_test.dart
│   │   ├── database_lifecycle_test.dart
│   │   └── exceptions_test.dart
│   ├── indexing/
│   │   ├── inverted_index_test.dart
│   │   ├── numeric_index_test.dart
│   │   ├── boolean_index_test.dart
│   │   ├── facet_index_test.dart
│   │   ├── geo_index_test.dart
│   │   └── sort_index_test.dart
│   ├── scoring/
│   │   ├── bm25_test.dart
│   │   ├── qps_test.dart
│   │   └── pt15_test.dart
│   ├── text/
│   │   ├── pipeline_test.dart
│   │   ├── tokenizer_test.dart
│   │   ├── normalizer_test.dart
│   │   ├── stemmer_test.dart
│   │   └── fuzzy_test.dart
│   ├── search/
│   │   ├── engine_test.dart
│   │   ├── filters_test.dart
│   │   ├── facets_test.dart
│   │   ├── grouping_test.dart
│   │   └── boost_test.dart
│   ├── highlight/
│   │   └── highlighter_test.dart
│   ├── persistence/
│   │   ├── json_serializer_test.dart
│   │   ├── cbor_serializer_test.dart
│   │   └── storage_test.dart
│   ├── isolate/
│   │   └── worker_test.dart
│   └── integration/
│       ├── edge_cases_test.dart
│       └── multi_language_test.dart
├── pubspec.yaml
├── analysis_options.yaml
├── CHANGELOG.md
├── LICENSE
├── NOTICE
└── README.md
```

---

## Phase 1: Foundation

### Task 1: Project Scaffolding

**Files:**
- Create: `packages/searchlight/pubspec.yaml`
- Create: `packages/searchlight/analysis_options.yaml`
- Create: `packages/searchlight/LICENSE`
- Create: `packages/searchlight/NOTICE`
- Create: `packages/searchlight/lib/searchlight.dart`

- [ ] **Step 1: Create the Dart package**

Use @dart-create skill conventions. Create `packages/searchlight/` with:

```yaml
# pubspec.yaml
name: searchlight
description: A full-text search engine for Dart with BM25 scoring, filters, facets, geosearch, and highlighting.
version: 0.1.0
repository: https://github.com/jhd-business/searchlight

environment:
  sdk: ^3.3.0

dependencies:
  cbor: ^6.5.1
  geobase: ^1.5.0
  r_tree: ^3.0.2
  snowball_stemmer: ^0.1.0
  unorm_dart: ^0.3.2

dev_dependencies:
  test: ^1.25.0
  very_good_analysis: ^10.0.0
```

```yaml
# analysis_options.yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 2: Create LICENSE (Apache 2.0), NOTICE, and CHANGELOG.md**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
```

```
# NOTICE
Searchlight
Copyright 2026 JHD Business

This project is inspired by Orama (https://github.com/oramasearch/orama)
Copyright Orama contributors, licensed under Apache License 2.0.

Searchlight is an independent pure Dart reimplementation — not a direct port.
```

- [ ] **Step 3: Create barrel file**

```dart
// lib/searchlight.dart
/// A full-text search engine for Dart.
library searchlight;
```

- [ ] **Step 4: Run `dart pub get` and `dart analyze`**

Run: `cd packages/searchlight && dart pub get && dart analyze`
Expected: No errors, no warnings.

- [ ] **Step 5: Commit**

```bash
git add packages/searchlight/
git commit -m "chore: scaffold searchlight package with deps and analysis"
```

---

### Task 2: DocId + Exception Hierarchy (Spec §2, §6)

**Files:**
- Create: `packages/searchlight/lib/src/core/doc_id.dart`
- Create: `packages/searchlight/lib/src/core/exceptions.dart`
- Create: `packages/searchlight/test/core/exceptions_test.dart`

> **Note:** DocId is extracted into its own file first because `DocumentNotFoundException` needs it. This avoids a dependency cycle with Task 4.

- [ ] **Step 0: Create DocId extension type**

```dart
// lib/src/core/doc_id.dart

/// A zero-cost type-safe wrapper for document identifiers.
extension type const DocId(int id) implements int {}
```

Export from barrel: `export 'src/core/doc_id.dart';`

- [ ] **Step 1: Write failing tests for exception types**

```dart
// test/core/exceptions_test.dart
import 'package:searchlight/src/core/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('SearchlightException', () {
    test('SchemaValidationException has message', () {
      const e = SchemaValidationException('Invalid field type');
      expect(e.message, 'Invalid field type');
      expect(e, isA<SearchlightException>());
    });

    test('DocumentValidationException includes field name', () {
      const e = DocumentValidationException('Type mismatch', field: 'price');
      expect(e.field, 'price');
      expect(e, isA<SearchlightException>());
    });

    test('DocumentNotFoundException includes DocId', () {
      final e = DocumentNotFoundException(const DocId(42));
      expect(e.message, contains('42'));
      expect(e.id, const DocId(42));
      expect(e, isA<SearchlightException>());
    });

    test('all exception types are exhaustively switchable', () {
      SearchlightException e = const SchemaValidationException('test');
      final result = switch (e) {
        SchemaValidationException() => 'schema',
        DocumentValidationException() => 'document',
        DocumentNotFoundException() => 'not_found',
        SerializationException() => 'serialization',
        StorageException() => 'storage',
        QueryException() => 'query',
      };
      expect(result, 'schema');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/searchlight && dart test test/core/exceptions_test.dart`
Expected: FAIL — file not found / classes not defined.

- [ ] **Step 3: Implement exception hierarchy**

```dart
// lib/src/core/exceptions.dart

/// Base exception for all Searchlight errors.
sealed class SearchlightException implements Exception {
  /// Human-readable error message.
  final String message;
  const SearchlightException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Schema definition error (invalid types, invalid nesting).
final class SchemaValidationException extends SearchlightException {
  const SchemaValidationException(super.message);
}

/// Document does not match schema.
final class DocumentValidationException extends SearchlightException {
  /// The field that failed validation, if applicable.
  final String? field;
  const DocumentValidationException(super.message, {this.field});
}

/// Document not found for update/patch/remove.
final class DocumentNotFoundException extends SearchlightException {
  /// The ID that was not found.
  final DocId id;
  DocumentNotFoundException(this.id) : super('Document not found: ${id.id}');
}

/// Serialization or deserialization failure.
final class SerializationException extends SearchlightException {
  const SerializationException(super.message);
}

/// Storage operation failure (file I/O, permission errors).
final class StorageException extends SearchlightException {
  /// The underlying cause, if available.
  final Object? cause;
  const StorageException(super.message, {this.cause});
}

/// Search query error (invalid field, incompatible filter).
final class QueryException extends SearchlightException {
  const QueryException(super.message);
}
```

- [ ] **Step 4: Export from barrel and run tests**

Add to `lib/searchlight.dart`:
```dart
export 'src/core/exceptions.dart';
```

Run: `cd packages/searchlight && dart test test/core/exceptions_test.dart`
Expected: ALL PASS.

- [ ] **Step 5: Run `dart analyze`**

Run: `cd packages/searchlight && dart analyze`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add sealed SearchlightException hierarchy"
```

---

### Task 3: Schema Types (Spec §2, §4)

**Files:**
- Create: `packages/searchlight/lib/src/core/schema.dart`
- Create: `packages/searchlight/test/core/schema_test.dart`

- [ ] **Step 1: Write failing tests for SchemaType, SchemaField, and Schema**

```dart
// test/core/schema_test.dart
import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaType', () {
    test('has all 9 leaf types (nested is structural via NestedField)', () {
      expect(SchemaType.values, hasLength(9));
      expect(SchemaType.values, contains(SchemaType.string));
      expect(SchemaType.values, contains(SchemaType.geopoint));
      expect(SchemaType.values, contains(SchemaType.enumArray));
    });
  });

  group('SchemaField', () {
    test('TypedField holds a SchemaType', () {
      const field = TypedField(SchemaType.string);
      expect(field.type, SchemaType.string);
    });

    test('NestedField holds child fields', () {
      const field = NestedField({
        'rating': TypedField(SchemaType.number),
      });
      expect(field.children, hasLength(1));
      expect(field.children['rating'], isA<TypedField>());
    });

    test('SchemaField is exhaustively switchable', () {
      const SchemaField field = TypedField(SchemaType.string);
      final result = switch (field) {
        TypedField() => 'typed',
        NestedField() => 'nested',
      };
      expect(result, 'typed');
    });
  });

  group('Schema', () {
    test('validates successfully with valid fields', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'price': const TypedField(SchemaType.number),
      });
      expect(schema.fields, hasLength(2));
    });

    test('throws on empty schema', () {
      expect(
        () => Schema({}),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('supports nested fields', () {
      final schema = Schema({
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(schema.fields['meta'], isA<NestedField>());
    });

    test('throws on empty nested field', () {
      expect(
        () => Schema({
          'meta': const NestedField({}),
        }),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('fieldPaths returns flattened dot-path list', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(schema.fieldPaths, containsAll(['title', 'meta.rating']));
    });

    test('typeAt returns the SchemaType for a dot-path', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(schema.typeAt('title'), SchemaType.string);
      expect(schema.typeAt('meta.rating'), SchemaType.number);
    });

    test('typeAt throws for unknown path', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
      });
      expect(
        () => schema.typeAt('unknown'),
        throwsA(isA<SchemaValidationException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/searchlight && dart test test/core/schema_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement schema types**

```dart
// lib/src/core/schema.dart
import 'exceptions.dart';

/// Supported field types in a Searchlight schema.
enum SchemaType {
  string,
  number,
  boolean,
  enumType,
  geopoint,
  stringArray,
  numberArray,
  booleanArray,
  enumArray,
}

/// A field definition in a schema.
sealed class SchemaField {
  const SchemaField();
}

/// A leaf field with a concrete type.
final class TypedField extends SchemaField {
  /// The data type of this field.
  final SchemaType type;
  const TypedField(this.type);
}

/// A nested object containing child fields.
final class NestedField extends SchemaField {
  /// Child field definitions.
  final Map<String, SchemaField> children;
  const NestedField(this.children);
}

/// A validated schema definition for a Searchlight database.
final class Schema {
  /// The top-level field definitions.
  final Map<String, SchemaField> fields;

  /// Creates a schema, validating that it is non-empty and well-formed.
  Schema(this.fields) {
    if (fields.isEmpty) {
      throw const SchemaValidationException('Schema must have at least one field');
    }
    _validate(fields, '');
  }

  void _validate(Map<String, SchemaField> fields, String prefix) {
    for (final entry in fields.entries) {
      switch (entry.value) {
        case TypedField():
          break; // valid leaf
        case NestedField(:final children):
          if (children.isEmpty) {
            throw SchemaValidationException(
              'Nested field "${prefix}${entry.key}" must have at least one child',
            );
          }
          _validate(children, '${prefix}${entry.key}.');
      }
    }
  }

  /// Returns all field paths as flattened dot-notation strings.
  List<String> get fieldPaths {
    final paths = <String>[];
    _collectPaths(fields, '', paths);
    return paths;
  }

  void _collectPaths(
    Map<String, SchemaField> fields,
    String prefix,
    List<String> paths,
  ) {
    for (final entry in fields.entries) {
      final path = '$prefix${entry.key}';
      switch (entry.value) {
        case TypedField():
          paths.add(path);
        case NestedField(:final children):
          _collectPaths(children, '$path.', paths);
      }
    }
  }

  /// Returns the [SchemaType] at the given dot-path.
  /// Throws [SchemaValidationException] if path does not exist.
  SchemaType typeAt(String path) {
    final parts = path.split('.');
    Map<String, SchemaField> current = fields;

    for (var i = 0; i < parts.length; i++) {
      final field = current[parts[i]];
      if (field == null) {
        throw SchemaValidationException('Unknown field path: $path');
      }
      if (i == parts.length - 1) {
        return switch (field) {
          TypedField(:final type) => type,
          NestedField() => throw SchemaValidationException(
              'Path "$path" points to a nested object, not a typed field',
            ),
        };
      }
      switch (field) {
        case NestedField(:final children):
          current = children;
        case TypedField():
          throw SchemaValidationException(
            'Path "$path" traverses through non-nested field "${parts[i]}"',
          );
      }
    }
    // Should not reach here
    throw SchemaValidationException('Invalid path: $path');
  }
}
```

- [ ] **Step 4: Export and run tests**

Add to `lib/searchlight.dart`:
```dart
export 'src/core/schema.dart';
```

Run: `cd packages/searchlight && dart test test/core/schema_test.dart`
Expected: ALL PASS.

- [ ] **Step 5: Run `dart analyze` and commit**

Run: `cd packages/searchlight && dart analyze`
Expected: No issues.

```bash
git add -A && git commit -m "feat: add SchemaType, SchemaField, and Schema with validation"
```

---

### Task 4: DocId, Document, and Core Types (Spec §2)

**Files:**
- Create: `packages/searchlight/lib/src/core/document.dart`
- Create: `packages/searchlight/lib/src/core/types.dart`
- Create: `packages/searchlight/test/core/document_test.dart`

- [ ] **Step 1: Write failing tests for DocId, Document, GeoPoint, and result types**

```dart
// test/core/document_test.dart
import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:test/test.dart';

void main() {
  group('DocId', () {
    test('wraps an int', () {
      const id = DocId(42);
      expect(id.id, 42);
      // Extension type — compiles to int at runtime
    });
  });

  group('Document', () {
    test('provides typed accessors', () {
      final doc = Document({'title': 'Hello', 'price': 9.99, 'active': true});
      expect(doc.getString('title'), 'Hello');
      expect(doc.getNumber('price'), 9.99);
      expect(doc.getBool('active'), true);
    });

    test('tryGet returns null for missing fields', () {
      final doc = Document({'title': 'Hello'});
      expect(doc.tryGetString('missing'), isNull);
      expect(doc.tryGetNumber('missing'), isNull);
    });

    test('toMap returns unmodifiable copy', () {
      final doc = Document({'title': 'Hello'});
      final map = doc.toMap();
      expect(map['title'], 'Hello');
      expect(() => map['new'] = 'value', throwsUnsupportedError);
    });

    test('getString throws on wrong type', () {
      final doc = Document({'price': 9.99});
      expect(() => doc.getString('price'), throwsA(isA<TypeError>()));
    });
  });

  group('GeoPoint', () {
    test('holds lat and lon', () {
      const point = GeoPoint(lat: 40.7128, lon: -74.006);
      expect(point.lat, 40.7128);
      expect(point.lon, -74.006);
    });
  });

  group('SearchResult', () {
    test('holds hits, count, and elapsed', () {
      final result = SearchResult(
        hits: [],
        count: 0,
        elapsed: Duration.zero,
      );
      expect(result.hits, isEmpty);
      expect(result.count, 0);
    });
  });

  group('SearchHit', () {
    test('holds id, score, and document', () {
      final hit = SearchHit(
        id: const DocId(1),
        score: 0.95,
        document: Document({'title': 'Test'}),
      );
      expect(hit.id, const DocId(1));
      expect(hit.score, 0.95);
      expect(hit.document.getString('title'), 'Test');
    });
  });

  group('FacetValue', () {
    test('holds value and count', () {
      const fv = FacetValue(value: 'electronics', count: 42);
      expect(fv.value, 'electronics');
      expect(fv.count, 42);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd packages/searchlight && dart test test/core/document_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement DocId, Document, and core types**

Create `lib/src/core/document.dart` with `DocId` extension type and `Document` class.
Create `lib/src/core/types.dart` with `GeoPoint`, `SearchResult`, `SearchHit`, `FacetValue`, `SortBy`, `SortOrder`, `GroupBy`, `FacetConfig`, `SearchMode`, `BatchResult`, `BatchError`.

Key code for `document.dart`:
```dart
extension type const DocId(int id) implements int {}

final class Document {
  final Map<String, Object?> _data;
  const Document(this._data);

  String getString(String field) => _data[field]! as String;
  num getNumber(String field) => _data[field]! as num;
  bool getBool(String field) => _data[field]! as bool;
  // ... typed accessors per spec

  String? tryGetString(String field) => _data[field] as String?;
  num? tryGetNumber(String field) => _data[field] as num?;
  // ... nullable variants

  Map<String, Object?> toMap() => Map.unmodifiable(_data);
}
```

Key code for `types.dart`:
```dart
final class GeoPoint {
  final double lat;
  final double lon;
  const GeoPoint({required this.lat, required this.lon});
}

final class SearchResult {
  final List<SearchHit> hits;
  final int count;
  final Duration elapsed;
  final Map<String, List<FacetValue>>? facets;
  final Map<String, List<SearchHit>>? groups;
  const SearchResult({
    required this.hits,
    required this.count,
    required this.elapsed,
    this.facets,
    this.groups,
  });
}

// ... SearchHit, FacetValue, SortBy, GroupBy, FacetConfig, SearchMode, etc.
```

- [ ] **Step 4: Export and run tests**

Add exports to `lib/searchlight.dart`:
```dart
export 'src/core/document.dart';
export 'src/core/types.dart';
```

Run: `cd packages/searchlight && dart test test/core/document_test.dart`
Expected: ALL PASS.

- [ ] **Step 5: Analyze and commit**

Run: `cd packages/searchlight && dart analyze`

```bash
git add -A && git commit -m "feat: add DocId, Document, GeoPoint, and result types"
```

---

### Task 5: Database Lifecycle — Create, Count, IsEmpty, Dispose (Spec §3)

**Files:**
- Create: `packages/searchlight/lib/src/core/database.dart`
- Create: `packages/searchlight/test/core/database_lifecycle_test.dart`

- [ ] **Step 1: Write failing tests for database creation and lifecycle**

```dart
// test/core/database_lifecycle_test.dart
import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight', () {
    late Searchlight db;

    setUp(() {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('creates with valid schema', () {
      expect(db, isNotNull);
      expect(db.isEmpty, isTrue);
      expect(db.count, 0);
    });

    test('defaults to BM25 algorithm', () {
      expect(db.algorithm, SearchAlgorithm.bm25);
    });

    test('defaults to English language', () {
      expect(db.language, 'en');
    });

    test('accepts custom algorithm', () {
      final qpsDb = Searchlight.create(
        schema: Schema({'title': const TypedField(SchemaType.string)}),
        algorithm: SearchAlgorithm.qps,
      );
      expect(qpsDb.algorithm, SearchAlgorithm.qps);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd packages/searchlight && dart test test/core/database_lifecycle_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement Searchlight class with create, count, isEmpty, dispose**

```dart
// lib/src/core/database.dart
import 'schema.dart';
import 'types.dart';

/// The search algorithm used for scoring.
enum SearchAlgorithm { bm25, qps, pt15 }

/// A full-text search engine instance.
final class Searchlight {
  final Schema schema;
  final SearchAlgorithm algorithm;
  final String language;

  Searchlight._({
    required this.schema,
    required this.algorithm,
    required this.language,
  });

  /// Creates a new Searchlight database.
  factory Searchlight.create({
    required Schema schema,
    SearchAlgorithm algorithm = SearchAlgorithm.bm25,
    String language = 'en',
  }) {
    return Searchlight._(
      schema: schema,
      algorithm: algorithm,
      language: language,
    );
  }

  /// Total number of indexed documents.
  int get count => _documents.length;

  /// Whether the database has no documents.
  bool get isEmpty => _documents.isEmpty;

  /// Releases resources. Flushes pending writes if any.
  Future<void> dispose() async {
    // Will be expanded when persistence/isolates are added
  }
}
```

- [ ] **Step 4: Export and run tests**

Add to barrel: `export 'src/core/database.dart';`

Run: `cd packages/searchlight && dart test test/core/database_lifecycle_test.dart`
Expected: ALL PASS.

- [ ] **Step 5: Analyze and commit**

```bash
dart analyze && git add -A && git commit -m "feat: add Searchlight.create with lifecycle methods"
```

---

### Task 6: Insert, GetById, Remove, Clear (Spec §3 — Slice 2)

**Files:**
- Modify: `packages/searchlight/lib/src/core/database.dart`
- Create: `packages/searchlight/test/core/database_crud_test.dart`

- [ ] **Step 1: Write failing tests for insert, getById, remove, removeMultiple, clear**

Tests should cover:
- `insert` returns a `DocId` and increments `count`
- `insert` with schema-invalid data throws `DocumentValidationException`
- `getById` returns the `Document` or `null`
- `remove` decrements count, returns silently if not found
- `removeMultiple` removes a list of IDs
- `clear` resets to empty

- [ ] **Step 2: Run tests — verify fail**

- [ ] **Step 3: Implement CRUD operations**

Add to `Searchlight`:
- `DocId insert(Map<String, Object?> data)` — validates against schema, stores, returns ID
- `Document? getById(DocId id)` — lookup from `_documents`
- `void remove(DocId id)` — remove from `_documents` (and indexes later)
- `void removeMultiple(List<DocId> ids)` — loop remove
- `void clear()` — clear `_documents` and all indexes

Document validation: walk the schema, check each field type matches the provided data. Missing fields are allowed (treated as null). Extra fields not in schema are rejected.

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add insert, getById, remove, clear CRUD operations"
```

---

### Task 7: Batch Insert with BatchResult (Spec §3 — Slice 3)

**Files:**
- Modify: `packages/searchlight/lib/src/core/database.dart`
- Create: `packages/searchlight/test/core/database_batch_test.dart`

- [ ] **Step 1: Write failing tests for insertMultiple**

Tests should cover:
- Batch insert of N documents returns N DocIds
- Partial failure: some docs invalid, others succeed — `BatchResult.errors` contains failures, `BatchResult.insertedIds` contains successes
- `batchSize` parameter affects processing (can verify via count)

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement `insertMultiple` returning `BatchResult`**
- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add insertMultiple with BatchResult error reporting"
```

---

### Task 8: Replace and Patch (Spec §3 — Slice 4)

**Files:**
- Modify: `packages/searchlight/lib/src/core/database.dart`
- Create: `packages/searchlight/test/core/database_update_test.dart`

- [ ] **Step 1: Write failing tests for replace and patch**

Tests should cover:
- `replace` fully replaces document data, validates against schema
- `replace` throws `DocumentNotFoundException` for unknown ID
- `patch` merges fields into existing document
- `patch` throws `DocumentNotFoundException` for unknown ID
- `patch` validates the merged result against schema
- After replace/patch, `getById` returns updated data

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement `replace` and `patch`**
- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add replace and patch document operations"
```

---

## Phase 2: Text Processing & Basic Search

### Task 9: Tokenizer Pipeline (Spec §7 — Slice 6)

**Files:**
- Create: `packages/searchlight/lib/src/text/normalizer.dart`
- Create: `packages/searchlight/lib/src/text/tokenizer.dart`
- Create: `packages/searchlight/lib/src/text/pipeline.dart`
- Create: `packages/searchlight/test/text/tokenizer_test.dart`
- Create: `packages/searchlight/test/text/pipeline_test.dart`

- [ ] **Step 1: Write failing tests for normalizer and tokenizer**

Test NFC normalization (é as single codepoint vs combining accent), Unicode-aware splitting (`\p{L}\p{Nd}`), lowercasing, and basic pipeline composition.

```dart
test('normalizer converts combining characters to NFC', () {
  final normalized = Normalizer.nfc('café'); // with combining accent
  expect(normalized, 'café'); // single codepoint
});

test('tokenizer splits on non-letter boundaries', () {
  final tokens = Tokenizer().tokenize('hello, world! 42');
  expect(tokens, ['hello', 'world', '42']);
});

test('tokenizer handles CJK text', () {
  final tokens = Tokenizer().tokenize('日本語テスト');
  expect(tokens, isNotEmpty);
});
```

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement Normalizer (wraps `unorm_dart`), Tokenizer (Unicode regex), and Pipeline**

Pipeline is a composable chain: `NFC → lowercase → tokenize → [stop words] → [stem]`

Index-time and search-time pipelines differ (search-time skips stop words).

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add tokenizer pipeline with NFC normalization"
```

---

### Task 10: Stemmer and Stop Words (Spec §7 — continues Slice 6)

**Files:**
- Create: `packages/searchlight/lib/src/text/stemmer.dart`
- Create: `packages/searchlight/lib/src/text/stop_words.dart`
- Create: `packages/searchlight/test/text/stemmer_test.dart`

- [ ] **Step 1: Write failing tests for stemming and stop word removal**

```dart
test('English stemmer reduces "running" to "run"', () {
  final stemmer = SearchlightStemmer(language: 'en');
  expect(stemmer.stem('running'), 'run');
});

test('stop words filters common English words', () {
  final stops = StopWords.forLanguage('en');
  expect(stops.contains('the'), isTrue);
  expect(stops.contains('searchlight'), isFalse);
});
```

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement stemmer wrapper (delegates to `snowball_stemmer`) and stop word sets**

Bundle stop word lists as `const Set<String>` per language. Start with English; other languages added in Slice 27.

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add stemmer and stop word filtering"
```

---

### Task 11: Inverted Index (Spec §7 — internal data structure)

**Files:**
- Create: `packages/searchlight/lib/src/indexing/inverted_index.dart`
- Create: `packages/searchlight/lib/src/indexing/posting_list.dart`
- Create: `packages/searchlight/test/indexing/inverted_index_test.dart`

- [ ] **Step 1: Write failing tests for inverted index**

```dart
test('index a document and retrieve posting list', () {
  final index = InvertedIndex();
  index.addDocument(const DocId(1), 'title', ['hello', 'world']);
  final postings = index.getPostings('hello');
  expect(postings, isNotNull);
  expect(postings!.docIds, contains(const DocId(1)));
});

test('remove document cleans up postings', () {
  final index = InvertedIndex();
  index.addDocument(const DocId(1), 'title', ['hello']);
  index.removeDocument(const DocId(1));
  final postings = index.getPostings('hello');
  expect(postings?.docIds, isNot(contains(const DocId(1))));
});

test('term frequency is tracked', () {
  final index = InvertedIndex();
  index.addDocument(const DocId(1), 'body', ['hello', 'hello', 'world']);
  final postings = index.getPostings('hello');
  expect(postings!.termFrequency(const DocId(1)), 2);
});
```

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement InvertedIndex and PostingList**

`InvertedIndex`: `HashMap<String, PostingList>` with `addDocument`, `removeDocument`, `getPostings`.

`PostingList`: stores `Map<DocId, _PostingEntry>` where entry has `termFrequency`, `fieldPositions`.

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add inverted index with posting lists"
```

---

### Task 12: BM25 Scorer (Spec §5 — Slice 5)

**Files:**
- Create: `packages/searchlight/lib/src/scoring/scorer.dart`
- Create: `packages/searchlight/lib/src/scoring/bm25.dart`
- Create: `packages/searchlight/test/scoring/bm25_test.dart`

- [ ] **Step 1: Write failing tests for BM25 scoring**

Use known-answer tests. Compute expected scores by hand for a small corpus.

```dart
test('BM25 scores document with matching term higher than non-matching', () {
  final scorer = Bm25Scorer();
  scorer.indexDocument(const DocId(1), 'title', ['hello', 'world']);
  scorer.indexDocument(const DocId(2), 'title', ['goodbye', 'world']);

  final score1 = scorer.score('hello', const DocId(1), 'title');
  final score2 = scorer.score('hello', const DocId(2), 'title');
  expect(score1, greaterThan(0));
  expect(score2, equals(0));
});

test('BM25 scores rare terms higher than common terms', () {
  // IDF: rare terms across corpus score higher
  final scorer = Bm25Scorer();
  scorer.indexDocument(const DocId(1), 'body', ['rare', 'common', 'common']);
  scorer.indexDocument(const DocId(2), 'body', ['common']);

  final rareScore = scorer.score('rare', const DocId(1), 'body');
  final commonScore = scorer.score('common', const DocId(1), 'body');
  expect(rareScore, greaterThan(commonScore));
});
```

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement abstract sealed Scorer hierarchy and Bm25Scorer**

Use `abstract sealed class Scorer` (abstract because it has no method implementations). Use `Map<String, Object?>` (not `dynamic`) for serialization. Include `serialize()` and `fromMap()` methods — these are needed by the persistence tasks later.

Scorer sealed class per spec §5. BM25 formula:
```
score = IDF * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (dl / avgdl))))
IDF = log(1 + (N - n + 0.5) / (n + 0.5))
```

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add sealed Scorer hierarchy with BM25 implementation"
```

---

### Task 13: Search Engine — Basic Full-Text Search (Spec §3 — Slice 5)

**Files:**
- Create: `packages/searchlight/lib/src/search/engine.dart`
- Create: `packages/searchlight/lib/src/search/filters.dart`
- Create: `packages/searchlight/lib/src/indexing/index_manager.dart`
- Create: `packages/searchlight/test/search/engine_test.dart`
- Modify: `packages/searchlight/lib/src/core/database.dart` — wire up search

- [ ] **Step 1: Write failing tests for end-to-end search**

```dart
test('search returns ranked results for matching term', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  db.insert({'title': 'Wireless Headphones'});
  db.insert({'title': 'Wired Earbuds'});
  db.insert({'title': 'Wireless Mouse'});

  final results = db.search(term: 'wireless');
  expect(results.count, 2);
  expect(results.hits, hasLength(2));
  expect(results.hits.first.score, greaterThan(0));
});

test('search with matchAll requires all terms', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  db.insert({'title': 'Wireless Headphones'});
  db.insert({'title': 'Wireless Mouse'});

  final results = db.search(
    term: 'wireless headphones',
    mode: SearchMode.matchAll,
  );
  expect(results.count, 1);
});

test('search with matchAny returns any matching term', () {
  // ...
});
```

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement SearchEngine, IndexManager, and wire into Searchlight.search()**

`IndexManager` creates per-field indexes based on schema. On `insert`, tokenizes string fields through the pipeline, feeds tokens to inverted index and scorer.

`SearchEngine.search()` tokenizes the query, scores each candidate document, sorts by score, applies limit/offset.

`Searchlight.search()` delegates to `SearchEngine`.

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add search engine with BM25 full-text search"
```

---

### Task 14: Typo Tolerance (Spec §7 — Slice 7)

**Files:**
- Create: `packages/searchlight/lib/src/text/fuzzy.dart`
- Create: `packages/searchlight/test/text/fuzzy_test.dart`
- Modify: `packages/searchlight/lib/src/search/engine.dart` — integrate fuzzy matching

- [ ] **Step 1: Write failing tests for Levenshtein distance and fuzzy search**

```dart
test('editDistance("kitten", "sitting") is 3', () {
  expect(editDistance('kitten', 'sitting'), 3);
});

test('search with tolerance=1 matches typos', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  db.insert({'title': 'Headphones'});
  final results = db.search(term: 'hedphones', tolerance: 1);
  expect(results.count, 1);
});
```

- [ ] **Step 2: Run tests — verify fail**
- [ ] **Step 3: Implement `editDistance` function and integrate into search engine**

When `tolerance > 0`, search engine finds all indexed terms within edit distance of each query term.

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Analyze and commit**

```bash
git add -A && git commit -m "feat: add typo tolerance with Levenshtein fuzzy matching"
```

---

### Task 14b: Radix Tree for Prefix Matching

**Files:**
- Create: `packages/searchlight/lib/src/indexing/radix_tree.dart`
- Create: `packages/searchlight/test/indexing/radix_tree_test.dart`

- [ ] **Step 1: Write failing tests for radix tree prefix lookups**

```dart
test('getByPrefix returns all terms with given prefix', () {
  final tree = SearchRadixTree();
  tree.insert('wireless');
  tree.insert('wired');
  tree.insert('bluetooth');
  expect(tree.getByPrefix('wir'), containsAll(['wireless', 'wired']));
  expect(tree.getByPrefix('blue'), ['bluetooth']);
  expect(tree.getByPrefix('xyz'), isEmpty);
});
```

- [ ] **Step 2-5: Implement (wrap `radix_tree` package or build in-house), test, commit**

Add `radix_tree: ^2.2.0` to pubspec if wrapping the package. Build the `SearchRadixTree` class that the inverted index populates during indexing. It must support `insert(term)`, `getByPrefix(prefix) → List<String>`, and `remove(term)`.

```bash
git add -A && git commit -m "feat: add radix tree for prefix matching"
```

---

### Task 15: Search Threshold and Prefix Mode (Slice 8)

**Files:**
- Modify: `packages/searchlight/lib/src/search/engine.dart`
- Modify: `packages/searchlight/test/search/engine_test.dart`

- [ ] **Step 1: Write failing tests for threshold, prefix search, and empty-term behavior**

```dart
test('threshold filters low-relevance results', () {
  // Insert docs where one is a weak match
  // Search with threshold: 0.5, verify weak match excluded
});

test('prefix mode matches partial last term', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  db.insert({'title': 'Wireless Headphones'});
  final results = db.search(term: 'wire', mode: SearchMode.prefix);
  expect(results.count, 1);
});

test('empty term returns all documents (enables filter-only queries)', () {
  final db = Searchlight.create(
    schema: Schema({
      'title': const TypedField(SchemaType.string),
      'price': const TypedField(SchemaType.number),
    }),
  );
  db.insert({'title': 'A', 'price': 10});
  db.insert({'title': 'B', 'price': 20});
  final results = db.search(term: '');
  expect(results.count, 2);
});
```

- [ ] **Step 2-5: Implement, test, commit**

For prefix: use the `SearchRadixTree` from Task 14b to find all indexed terms starting with the query prefix.

```bash
git add -A && git commit -m "feat: add search threshold, prefix mode, and empty-term support"
```

---

## Phase 3: Filtering & Facets

### Task 16: Filter DSL and Numeric Filtering (Spec §2, §3 — Slices 9, 14)

**Files:**
- Modify: `packages/searchlight/lib/src/search/filters.dart` — define Filter sealed hierarchy
- Create: `packages/searchlight/lib/src/indexing/numeric_index.dart`
- Create: `packages/searchlight/test/search/filters_test.dart`
- Create: `packages/searchlight/test/indexing/numeric_index_test.dart`

- [ ] **Step 1: Write failing tests**

Test the `Filter` sealed hierarchy, `NumericIndex` range queries, and end-to-end search with `where` filters.

```dart
test('between filter matches documents in range', () {
  final db = Searchlight.create(
    schema: Schema({
      'title': const TypedField(SchemaType.string),
      'price': const TypedField(SchemaType.number),
    }),
  );
  db.insert({'title': 'Cheap', 'price': 10});
  db.insert({'title': 'Mid', 'price': 50});
  db.insert({'title': 'Expensive', 'price': 200});

  final results = db.search(
    term: '',
    where: {'price': between(20, 100)},
  );
  expect(results.count, 1);
  expect(results.hits.first.document.getNumber('price'), 50);
});
```

- [ ] **Step 2-5: Implement, test, commit**

`NumericIndex` uses `SplayTreeMap<num, Set<DocId>>` for O(log n) range queries.

```bash
git add -A && git commit -m "feat: add Filter hierarchy and numeric filtering"
```

---

### Task 17: Boolean Filtering (Slice 10)

**Files:**
- Create: `packages/searchlight/lib/src/indexing/boolean_index.dart`
- Create: `packages/searchlight/test/indexing/boolean_index_test.dart`

- [ ] **Step 1: Write failing tests for boolean index and eq(true/false) filter**
- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add boolean index and eq filter"
```

---

### Task 18: Enum Fields and Facets (Slice 11)

**Files:**
- Create: `packages/searchlight/lib/src/indexing/facet_index.dart`
- Create: `packages/searchlight/lib/src/search/facets.dart`
- Create: `packages/searchlight/test/search/facets_test.dart`

- [ ] **Step 1: Write failing tests for facet counting and enum filtering**

```dart
test('facets return category counts', () {
  final db = Searchlight.create(
    schema: Schema({
      'title': const TypedField(SchemaType.string),
      'category': const TypedField(SchemaType.enumType),
    }),
  );
  db.insert({'title': 'Phone', 'category': 'electronics'});
  db.insert({'title': 'Laptop', 'category': 'electronics'});
  db.insert({'title': 'Chair', 'category': 'furniture'});

  final results = db.search(
    term: '',
    facets: {'category': FacetConfig(limit: 10)},
  );
  expect(results.facets!['category'], hasLength(2));
  // electronics: 2, furniture: 1
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add facet index and enum filtering"
```

---

### Task 19: Array Fields (Slice 12)

**Files:**
- Modify: `packages/searchlight/lib/src/indexing/index_manager.dart`
- Create: `packages/searchlight/test/indexing/array_fields_test.dart`

- [ ] **Step 1: Write failing tests for array field indexing**

Test `stringArray`, `numberArray`, `booleanArray`, `enumArray` — each value in the array should be indexed individually. A search for one element should match the document.

- [ ] **Step 2-5: Implement, test, commit**

Index manager detects array types and iterates values, feeding each to the appropriate index.

```bash
git add -A && git commit -m "feat: add array field indexing"
```

---

### Task 20: Nested Objects (Slice 13)

**Files:**
- Modify: `packages/searchlight/lib/src/indexing/index_manager.dart`
- Create: `packages/searchlight/test/indexing/nested_fields_test.dart`

- [ ] **Step 1: Write failing tests for nested field indexing and filtering**

```dart
test('nested field is searchable via dot path', () {
  final db = Searchlight.create(
    schema: Schema({
      'meta': const NestedField({
        'author': TypedField(SchemaType.string),
        'rating': TypedField(SchemaType.number),
      }),
    }),
  );
  db.insert({'meta': {'author': 'Alice', 'rating': 4.5}});
  db.insert({'meta': {'author': 'Bob', 'rating': 3.0}});

  final results = db.search(
    term: 'Alice',
    properties: ['meta.author'],
  );
  expect(results.count, 1);
});
```

- [ ] **Step 2-5: Implement, test, commit**

Index manager walks nested schema, flattens to dot-paths, extracts values from nested document maps.

```bash
git add -A && git commit -m "feat: add nested object indexing with dot-path access"
```

---

### Task 21: Compound Filters (Slice 14)

**Files:**
- Modify: `packages/searchlight/test/search/filters_test.dart`

- [ ] **Step 1: Write failing tests for multiple where conditions**

```dart
test('multiple where conditions are ANDed', () {
  // Insert docs with various price/active combinations
  // Search with where: { 'price': between(10, 100), 'active': eq(true) }
  // Verify only docs matching BOTH conditions returned
});
```

- [ ] **Step 2-5: Implement, test, commit**

All `where` conditions are ANDed (intersection of matching DocId sets).

```bash
git add -A && git commit -m "feat: add compound filter support (AND semantics)"
```

---

## Phase 4: Sorting, Grouping, Boosting, Geosearch

### Task 22: Sorting (Slice 15)

**Files:**
- Create: `packages/searchlight/lib/src/indexing/sort_index.dart`
- Modify: `packages/searchlight/lib/src/search/engine.dart`
- Create: `packages/searchlight/test/search/sorting_test.dart`

- [ ] **Step 1: Write failing tests for single-field and multi-field sorting**

```dart
test('sortBy sorts results by field ascending', () {
  // Insert 3 docs with different prices
  // Search with sortBy: SortBy(field: 'price', order: SortOrder.asc)
  // Verify prices are in ascending order
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add result sorting by field"
```

---

### Task 23: Grouping (Slice 16)

**Files:**
- Create: `packages/searchlight/lib/src/search/grouping.dart`
- Create: `packages/searchlight/test/search/grouping_test.dart`

- [ ] **Step 1: Write failing tests for groupBy**
- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add result grouping by field"
```

---

### Task 24: Field Boosting (Slice 17)

**Files:**
- Create: `packages/searchlight/lib/src/search/boost.dart`
- Create: `packages/searchlight/test/search/boost_test.dart`

- [ ] **Step 1: Write failing tests for field boosting**

```dart
test('boosted field ranks document higher', () {
  final db = Searchlight.create(
    schema: Schema({
      'title': const TypedField(SchemaType.string),
      'body': const TypedField(SchemaType.string),
    }),
  );
  db.insert({'title': 'Dart', 'body': 'A programming language'});
  db.insert({'title': 'Programming', 'body': 'Learn Dart today'});

  final results = db.search(
    term: 'Dart',
    boost: {'title': 2.0},
  );
  // Doc with 'Dart' in title should rank higher
  expect(results.hits.first.document.getString('title'), 'Dart');
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add field-level boosting"
```

---

### Task 25: Geosearch (Slice 18)

**Files:**
- Create: `packages/searchlight/lib/src/indexing/geo_index.dart`
- Create: `packages/searchlight/test/indexing/geo_index_test.dart`

- [ ] **Step 1: Write failing tests for geopoint indexing and radius filtering**

```dart
test('geoRadius filter returns documents within radius', () {
  final db = Searchlight.create(
    schema: Schema({
      'name': const TypedField(SchemaType.string),
      'location': const TypedField(SchemaType.geopoint),
    }),
  );
  // NYC
  db.insert({'name': 'NYC Cafe', 'location': const GeoPoint(lat: 40.7128, lon: -74.006)});
  // LA
  db.insert({'name': 'LA Cafe', 'location': const GeoPoint(lat: 34.0522, lon: -118.2437)});

  final results = db.search(
    term: '',
    where: {'location': geoRadius(lat: 40.71, lon: -74.00, radius: 10000)},
  );
  expect(results.count, 1);
  expect(results.hits.first.document.getString('name'), 'NYC Cafe');
});
```

- [ ] **Step 2-5: Implement using `geobase` for Haversine and `r_tree` for spatial indexing**

Strategy: bounding box pre-filter via R-tree, then Haversine exact distance check on candidates.

```bash
git add -A && git commit -m "feat: add geosearch with radius filtering"
```

---

## Phase 5: Highlighting

### Task 26: Standalone Highlighter (Slice 19)

**Files:**
- Create: `packages/searchlight/lib/src/highlight/positions.dart`
- Create: `packages/searchlight/lib/src/highlight/highlighter.dart`
- Create: `packages/searchlight/test/highlight/highlighter_test.dart`

- [ ] **Step 1: Write failing tests for highlight positions, trim, case sensitivity, whole words**

```dart
test('highlight returns correct positions', () {
  final h = Highlighter();
  final result = h.highlight('The quick brown fox', 'brown fox');
  expect(result.positions, hasLength(2));
  expect(result.positions[0].start, 10);
  expect(result.positions[0].end, 15);
});

test('trim returns excerpt centered around matches', () {
  final h = Highlighter();
  final result = h.highlight(
    'The quick brown fox jumps over the lazy dog',
    'brown',
  );
  final trimmed = result.trim(20);
  expect(trimmed, contains('brown'));
  expect(trimmed.length, lessThanOrEqualTo(25)); // 20 + ellipsis
});

test('caseSensitive mode only matches exact case', () {
  final h = Highlighter(caseSensitive: true);
  final result = h.highlight('Hello hello HELLO', 'hello');
  expect(result.positions, hasLength(1)); // only lowercase match
});

test('wholeWords mode does not match partial words', () {
  final h = Highlighter(wholeWords: true);
  final result = h.highlight('unbroken broken', 'broken');
  expect(result.positions, hasLength(1)); // only standalone 'broken'
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add standalone highlighter with positions and trim"
```

---

### Task 27: Pipeline-Aware Highlighter + SearchHit.highlights (Slice 20)

**Files:**
- Modify: `packages/searchlight/lib/src/highlight/highlighter.dart`
- Modify: `packages/searchlight/lib/src/core/types.dart` — add `highlights` to SearchHit
- Modify: `packages/searchlight/lib/src/search/engine.dart` — compute highlights
- Create: `packages/searchlight/test/highlight/pipeline_highlighter_test.dart`

- [ ] **Step 1: Write failing tests for pipeline-aware highlighting and SearchHit.highlights**

```dart
test('pipeline-aware highlighter matches stemmed terms', () {
  // 'running' and 'run' should match because stemmer reduces both
});

test('search results include per-field highlights', () {
  final db = Searchlight.create(
    schema: Schema({
      'title': const TypedField(SchemaType.string),
      'body': const TypedField(SchemaType.string),
    }),
  );
  db.insert({'title': 'Brown Fox', 'body': 'The fox is brown and quick'});

  final results = db.search(term: 'brown fox', properties: ['title', 'body']);
  final hit = results.hits.first;
  expect(hit.highlights, isNotNull);
  expect(hit.highlights!['title']?.positions, isNotEmpty);
  expect(hit.highlights!['body']?.positions, isNotEmpty);
});
```

- [ ] **Step 2-5: Implement, test, commit**

Add `Map<String, HighlightResult>? highlights` to `SearchHit`. Search engine computes highlights for each hit's searched fields.

```bash
git add -A && git commit -m "feat: add pipeline-aware highlighter and SearchHit.highlights"
```

---

## Phase 6: Alternative Scoring Algorithms

### Task 28: QPS Scorer (Slice 21)

**Files:**
- Create: `packages/searchlight/lib/src/scoring/qps.dart`
- Create: `packages/searchlight/test/scoring/qps_test.dart`

- [ ] **Step 1: Write failing tests for QPS proximity-based scoring**

```dart
test('QPS scores terms closer together higher', () {
  final scorer = QpsScorer();
  // Doc1: 'brown fox' (adjacent)
  // Doc2: 'brown ... fox' (far apart)
  // Doc1 should score higher for query 'brown fox'
});
```

- [ ] **Step 2-5: Implement, test, commit**

Study Orama's QPS documentation for algorithm details. Key idea: divide document into quantums, score based on how many query terms appear in the same quantum.

```bash
git add -A && git commit -m "feat: add QPS (Quantum Proximity Scoring) algorithm"
```

---

### Task 29: PT15 Scorer (Slice 22)

**Files:**
- Create: `packages/searchlight/lib/src/scoring/pt15.dart`
- Create: `packages/searchlight/test/scoring/pt15_test.dart`

- [ ] **Step 1: Write failing tests for PT15 positional scoring**

```dart
test('PT15 scores terms in earlier positions higher', () {
  // Doc1: 'dart language for ...' (dart at position 0)
  // Doc2: '... written in dart' (dart at position 3)
  // Doc1 should score higher for query 'dart'
});
```

- [ ] **Step 2-5: Implement, test, commit**

15 fixed position buckets. Tokens in bucket 0 get highest score, linearly decreasing.

```bash
git add -A && git commit -m "feat: add PT15 (Positional Token 15) algorithm"
```

---

### Task 30: Algorithm Migration — reindex() (Slice 23)

**Files:**
- Modify: `packages/searchlight/lib/src/core/database.dart`
- Create: `packages/searchlight/test/core/database_reindex_test.dart`

- [ ] **Step 1: Write failing tests for reindex**

```dart
test('reindex creates new DB with different algorithm', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  db.insert({'title': 'Hello World'});

  final newDb = db.reindex(algorithm: SearchAlgorithm.qps);
  expect(newDb.algorithm, SearchAlgorithm.qps);
  expect(newDb.count, 1);
  final results = newDb.search(term: 'hello');
  expect(results.count, 1);
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add reindex for algorithm migration"
```

---

## Phase 7: Persistence

### Task 31: JSON Serialization with Format Versioning (Slice 24)

**Files:**
- Create: `packages/searchlight/lib/src/persistence/format.dart`
- Create: `packages/searchlight/lib/src/persistence/json_serializer.dart`
- Create: `packages/searchlight/test/persistence/json_serializer_test.dart`

- [ ] **Step 1: Write failing tests for JSON round-trip**

```dart
test('toJson/fromJson round-trip preserves data and search results', () {
  final db = Searchlight.create(
    schema: Schema({
      'title': const TypedField(SchemaType.string),
      'price': const TypedField(SchemaType.number),
    }),
  );
  db.insert({'title': 'Widget', 'price': 9.99});

  final json = db.toJson();
  final restored = Searchlight.fromJson(json);

  expect(restored.count, 1);
  final results = restored.search(term: 'widget');
  expect(results.count, 1);
  expect(results.hits.first.document.getNumber('price'), 9.99);
});

test('JSON includes format version', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  final json = db.toJson();
  expect(json['formatVersion'], currentFormatVersion);
});

test('fromJson rejects incompatible version', () {
  expect(
    () => Searchlight.fromJson({'formatVersion': 999}),
    throwsA(isA<SerializationException>()),
  );
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add JSON serialization with format versioning"
```

---

### Task 32: CBOR Serialization (Slice 25)

**Files:**
- Create: `packages/searchlight/lib/src/persistence/cbor_serializer.dart`
- Create: `packages/searchlight/test/persistence/cbor_serializer_test.dart`

- [ ] **Step 1: Write failing tests for CBOR round-trip**

Same pattern as JSON but with `serialize()` / `deserialize()` returning `Uint8List`.

```dart
test('serialize/deserialize CBOR round-trip', () {
  final db = Searchlight.create(...);
  db.insert({'title': 'Widget', 'price': 9.99});

  final bytes = db.serialize();
  expect(bytes, isA<Uint8List>());

  final restored = Searchlight.deserialize(bytes);
  expect(restored.count, 1);
});

test('deserialize rejects corrupt data', () {
  expect(
    () => Searchlight.deserialize(Uint8List.fromList([0, 1, 2, 3])),
    throwsA(isA<SerializationException>()),
  );
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add CBOR binary serialization"
```

---

### Task 33: Storage Interface + FileStorage (Slice 26)

**Files:**
- Create: `packages/searchlight/lib/src/persistence/storage.dart`
- Create: `packages/searchlight/test/persistence/storage_test.dart`

- [ ] **Step 1: Write failing tests for SearchlightStorage interface and FileStorage**

```dart
test('FileStorage saves and loads index', () async {
  final dir = Directory.systemTemp.createTempSync();
  final path = '${dir.path}/test.cbor';
  final storage = FileStorage(path: path);

  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
    storage: storage,
  );
  db.insert({'title': 'Hello'});
  await db.persist();

  final restored = await Searchlight.restore(storage: storage);
  expect(restored.count, 1);

  dir.deleteSync(recursive: true);
});
```

- [ ] **Step 2-5: Implement, test, commit**

```bash
git add -A && git commit -m "feat: add SearchlightStorage interface and FileStorage"
```

---

## Phase 8: Multi-Language, Isolates, Edge Cases

### Task 34: Multi-Language Stemming and Stop Words (Slice 27)

**Files:**
- Modify: `packages/searchlight/lib/src/text/stemmer.dart`
- Modify: `packages/searchlight/lib/src/text/stop_words.dart`
- Create: `packages/searchlight/test/integration/multi_language_test.dart`

- [ ] **Step 1: Write failing tests for non-English languages**

```dart
test('German stemmer reduces "Häuser" to "Haus"', () {
  final stemmer = SearchlightStemmer(language: 'de');
  expect(stemmer.stem('Häuser'), 'Haus');
});

test('French stop words include "le", "la"', () {
  final stops = StopWords.forLanguage('fr');
  expect(stops.contains('le'), isTrue);
});

test('search works with German language', () {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
    language: 'de',
  );
  db.insert({'title': 'Die Häuser sind groß'});
  final results = db.search(term: 'Haus');
  expect(results.count, 1);
});
```

- [ ] **Step 2-5: Add stop word lists for all 29 snowball_stemmer languages, test, commit**

```bash
git add -A && git commit -m "feat: add multi-language stemming and stop words (29 languages)"
```

---

### Task 35: Isolate Support (Slice 28)

**Files:**
- Create: `packages/searchlight/lib/src/isolate/worker.dart`
- Create: `packages/searchlight/lib/src/isolate/transfer.dart`
- Create: `packages/searchlight/test/isolate/worker_test.dart`

- [ ] **Step 1: Write failing tests for background index building**

```dart
test('buildInBackground indexes documents on a separate isolate', () async {
  final db = Searchlight.create(
    schema: Schema({'title': const TypedField(SchemaType.string)}),
  );
  final docs = List.generate(1000, (i) => {'title': 'Document $i'});

  await db.buildInBackground(docs);
  expect(db.count, 1000);
  final results = db.search(term: 'Document 42');
  expect(results.count, greaterThan(0));
});
```

- [ ] **Step 2-5: Implement using `Isolate.run` and CBOR transfer, test, commit**

Strategy: serialize documents, send to isolate, build index, serialize index, transfer back via `TransferableTypedData`.

```bash
git add -A && git commit -m "feat: add isolate support for background index building"
```

---

### Task 36: Edge Cases (Slice 29)

**Files:**
- Create: `packages/searchlight/test/integration/edge_cases_test.dart`

- [ ] **Step 1: Write tests for all edge cases**

```dart
test('search on empty database returns empty results', () { ... });
test('search with empty string term returns all documents', () { ... });
test('insert duplicate data creates separate documents', () { ... });
test('remove non-existent ID does nothing', () { ... });
test('replace correctly re-indexes all fields', () { ... });
test('patch correctly re-indexes changed fields only', () { ... });
test('search with filter on non-existent field throws QueryException', () { ... });
test('very long document content is indexed correctly', () { ... });
test('special characters in search term are handled', () { ... });
test('unicode emoji in content does not crash tokenizer', () { ... });
```

- [ ] **Step 2-5: Fix any failures, commit**

```bash
git add -A && git commit -m "test: add edge case integration tests"
```

---

### Task 36b: DocumentAdapter Interface (Spec §10)

**Files:**
- Create: `packages/searchlight/lib/src/core/document_adapter.dart`

- [ ] **Step 1: Create the abstract interface**

```dart
// lib/src/core/document_adapter.dart

import 'document.dart';

/// Interface for extracting searchable content from any source format.
///
/// Implementations convert source data (PDF bytes, HTML, CSV, etc.)
/// into [Document] instances that can be indexed by Searchlight.
abstract class DocumentAdapter<T> {
  /// Convert a source object into one or more indexable documents.
  ///
  /// Returns a list because one source (e.g., a PDF) may produce
  /// multiple documents (one per page/section).
  List<Document> toDocuments(T source);
}
```

- [ ] **Step 2: Export from barrel and analyze**

```bash
dart analyze && git add -A && git commit -m "feat: add DocumentAdapter interface"
```

---

### Task 37: Barrel File + Final Cleanup

**Files:**
- Modify: `packages/searchlight/lib/searchlight.dart`
- Create: `packages/searchlight/README.md` (minimal — required for pub.dev)

- [ ] **Step 1: Ensure barrel file exports all public API**

```dart
// lib/searchlight.dart
library searchlight;

export 'src/core/database.dart';
export 'src/core/doc_id.dart';
export 'src/core/document.dart';
export 'src/core/document_adapter.dart';
export 'src/core/exceptions.dart';
export 'src/core/schema.dart';
export 'src/core/types.dart';
export 'src/highlight/highlighter.dart';
export 'src/highlight/positions.dart';
export 'src/persistence/storage.dart';
export 'src/search/filters.dart';
// Only public API — not internal index structures
```

- [ ] **Step 2: Run full test suite**

Run: `cd packages/searchlight && dart test`
Expected: ALL PASS.

- [ ] **Step 3: Run `dart analyze`**

Run: `cd packages/searchlight && dart analyze`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: finalize barrel exports and cleanup"
```

---

## Summary

| Phase | Tasks | Slices Covered |
|-------|-------|---------------|
| 1. Foundation | 1–8 | Scaffolding, DocId, exceptions, schema, Document/types, DB lifecycle, CRUD, batch, replace/patch |
| 2. Text & Search | 9–15 | Tokenizer, stemmer, inverted index, BM25, search engine, fuzzy, radix tree, threshold/prefix |
| 3. Filtering | 16–21 | Filter DSL, numeric, boolean, enum/facets, arrays, nested, compound filters |
| 4. Sort/Group/Geo | 22–25 | Sorting, grouping, boosting, geosearch |
| 5. Highlighting | 26–27 | Standalone highlighter, pipeline-aware, SearchHit.highlights |
| 6. Alt Algorithms | 28–30 | QPS, PT15, reindex migration |
| 7. Persistence | 31–33 | JSON, CBOR, storage interface |
| 8. Advanced | 34–37 | Multi-language, isolates, edge cases, DocumentAdapter, cleanup |
