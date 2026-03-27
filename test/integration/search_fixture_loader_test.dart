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

  test(
    'throws clear error when corpus top-level json is not an array',
    () async {
      final originalDirectory = Directory.current;
      final temp = await Directory.systemTemp.createTemp(
        'search_fixture_loader_test_',
      );
      final fixturesDir = Directory('${temp.path}/test/fixtures')
        ..createSync(recursive: true);

      File(
        '${fixturesDir.path}/search_corpus.json',
      ).writeAsStringSync('{"not":"an-array"}');
      File(
        '${fixturesDir.path}/search_expectations.json',
      ).writeAsStringSync('[]');

      try {
        Directory.current = temp;
        await expectLater(
          loadSearchFixture(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('search_corpus.json must be a JSON array'),
            ),
          ),
        );
      } finally {
        Directory.current = originalDirectory;
        await temp.delete(recursive: true);
      }
    },
  );
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final marker = File('${current.path}/test/fixtures/search_corpus.json');
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
