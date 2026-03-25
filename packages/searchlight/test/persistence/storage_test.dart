// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('FileStorage', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('searchlight_test_');
      tempPath = '${tempDir.path}/test.cbor';
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves and loads bytes', () async {
      final storage = FileStorage(path: tempPath);
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      await storage.save(data);
      final loaded = await storage.load();

      expect(loaded, equals(data));
    });

    test('load returns null for non-existent file', () async {
      final storage = FileStorage(
        path: '${tempDir.path}/does_not_exist.cbor',
      );

      final loaded = await storage.load();

      expect(loaded, isNull);
    });
  });

  group('persist()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('searchlight_persist_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves to storage', () async {
      final storage = FileStorage(path: '${tempDir.path}/db.cbor');
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )..insert({'id': 'doc-1', 'title': 'Hello'});

      await db.persist(storage: storage);

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded, isNotEmpty);
    });
  });

  group('restore()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('searchlight_restore_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('loads from storage and returns working Searchlight', () async {
      final storage = FileStorage(path: '${tempDir.path}/db.cbor');

      // Persist a database
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'doc-1', 'title': 'Dart Programming'})
        ..insert({'id': 'doc-2', 'title': 'Flutter Widgets'});
      await db.persist(storage: storage);

      // Restore from the same storage
      final restored = await Searchlight.restore(storage: storage);

      expect(restored.count, equals(2));

      // Search should work on the restored database
      final results = restored.search(term: 'Dart');
      expect(results.count, equals(1));
      expect(results.hits.first.id, equals('doc-1'));
    });

    test('throws StorageException when storage is empty', () async {
      final storage = FileStorage(path: '${tempDir.path}/empty.cbor');

      expect(
        () => Searchlight.restore(storage: storage),
        throwsA(isA<StorageException>()),
      );
    });
  });
}
