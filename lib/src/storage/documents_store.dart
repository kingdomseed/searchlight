import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/document.dart';

/// Public contract for Searchlight document stores.
abstract interface class SearchlightDocumentsStore {
  /// Returns the number of stored documents.
  int get count;

  /// Returns all internal IDs currently present in the store.
  Iterable<DocId> get internalIds;

  /// Returns whether [externalId] is already present.
  bool containsExternalId(String externalId);

  /// Returns the external ID for [internalId], if known.
  String? getExternalId(DocId internalId);

  /// Returns the document for [externalId], if present.
  Document? getByExternalId(String externalId);

  /// Returns the document for [internalId], if present.
  Document? getByInternalId(DocId internalId);

  /// Removes the document for [externalId], if present.
  bool removeByExternalId(String externalId);

  /// Stores [document] under [externalId] and [internalId].
  bool store({
    required DocId internalId,
    required String externalId,
    required Document document,
  });

  /// Restores an exact persisted [document] without runtime transforms.
  void restore({
    required DocId internalId,
    required String externalId,
    required Document document,
  });

  /// Serializes the store payload as
  /// `internalId -> JSON-compatible document map`.
  Map<String, Object?> save();
}

/// Default in-memory implementation used by Searchlight.
final class InMemorySearchlightDocumentsStore
    implements SearchlightDocumentsStore {
  final Map<DocId, Document> _documents = {};
  final Map<String, DocId> _externalToInternal = {};
  final Map<DocId, String> _internalToExternal = {};

  @override
  int get count => _documents.length;

  @override
  Iterable<DocId> get internalIds => _documents.keys;

  @override
  bool containsExternalId(String externalId) =>
      _externalToInternal.containsKey(externalId);

  @override
  String? getExternalId(DocId internalId) => _internalToExternal[internalId];

  @override
  Document? getByExternalId(String externalId) {
    final internalId = _externalToInternal[externalId];
    if (internalId == null) {
      return null;
    }
    return _documents[internalId];
  }

  @override
  Document? getByInternalId(DocId internalId) => _documents[internalId];

  @override
  bool removeByExternalId(String externalId) {
    final internalId = _externalToInternal.remove(externalId);
    if (internalId == null) {
      return false;
    }
    _internalToExternal.remove(internalId);
    return _documents.remove(internalId) != null;
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
        for (final entry in _documents.entries)
          entry.key.id.toString():
              Map<String, Object?>.from(entry.value.toMap()),
      };

  @override
  bool store({
    required DocId internalId,
    required String externalId,
    required Document document,
  }) {
    if (_externalToInternal.containsKey(externalId)) {
      return false;
    }
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;
    _documents[internalId] = document;
    return true;
  }

  @override
  void restore({
    required DocId internalId,
    required String externalId,
    required Document document,
  }) {
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;
    _documents[internalId] = document;
  }
}
