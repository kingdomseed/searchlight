// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

/// Abstract interface for persisting serialized Searchlight data.
///
/// Implementations handle the actual I/O — file system, in-memory buffer,
/// network, etc.
abstract class SearchlightStorage {
  /// Saves [data] to the backing store.
  Future<void> save(Uint8List data);

  /// Loads data from the backing store.
  ///
  /// Returns `null` if no data has been saved yet.
  Future<Uint8List?> load();
}

/// A [SearchlightStorage] backed by a single file on disk.
///
/// Writes bytes with [File.writeAsBytes] and reads with [File.readAsBytes].
final class FileStorage implements SearchlightStorage {
  /// Creates a [FileStorage] that reads/writes to the file at [path].
  FileStorage({required this.path});

  /// The file system path to the storage file.
  final String path;

  @override
  Future<void> save(Uint8List data) async {
    await File(path).writeAsBytes(data);
  }

  @override
  Future<Uint8List?> load() async {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }
}
