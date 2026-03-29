import 'package:searchlight/searchlight.dart';

SearchlightIndexComponent testIndexComponent({
  required String id,
  required SearchAlgorithm forcedAlgorithm,
}) {
  return SearchlightIndexComponent(
    id: id,
    create: ({
      required schema,
      required algorithm,
    }) {
      final _ = algorithm;
      return SearchIndex.create(schema: schema, algorithm: forcedAlgorithm);
    },
  );
}

SearchlightPlugin<Object?> testIndexPlugin({
  required String name,
  required String componentId,
  required SearchAlgorithm forcedAlgorithm,
}) {
  return SearchlightPlugin(
    name: name,
    components: SearchlightComponents(
      index: testIndexComponent(
        id: componentId,
        forcedAlgorithm: forcedAlgorithm,
      ),
    ),
  );
}
