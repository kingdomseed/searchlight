import 'dart:io';

import 'package:test/test.dart';

import '../helpers/search_fixture_loader.dart';

void main() {
  test('loads public search corpus and expectations', () async {
    final fixture = await loadSearchFixture();

    expect(fixture.records, isNotEmpty);
    expect(fixture.records.first.title, isNotEmpty);
    expect(fixture.expectations, isNotEmpty);
    expect(fixture.expectations.first.term, isNotEmpty);
  });

  test('loads fixture when current directory is repo root', () async {
    final originalDirectory = Directory.current;
    final repoRoot = _findRepoRoot(originalDirectory);

    try {
      Directory.current = repoRoot;
      final fixture = await loadSearchFixture();
      expect(fixture.records, isNotEmpty);
      expect(fixture.expectations, isNotEmpty);
    } finally {
      Directory.current = originalDirectory;
    }
  });
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final marker = File(
      '${current.path}/packages/searchlight/test/fixtures/search_corpus.json',
    );
    if (marker.existsSync()) {
      return current;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      fail('Could not locate repository root from ${start.path}');
    }
    current = parent;
  }
}
