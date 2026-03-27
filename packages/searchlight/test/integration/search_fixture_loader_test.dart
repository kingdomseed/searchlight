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
}
