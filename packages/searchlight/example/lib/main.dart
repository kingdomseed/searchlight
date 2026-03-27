import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:searchlight/searchlight.dart';

void main() {
  runApp(const SearchValidationApp());
}

enum DataSourceMode {
  publicCorpus,
  localCorpus,
  localSnapshot,
}

class SearchValidationApp extends StatelessWidget {
  const SearchValidationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SearchValidationScreen(),
    );
  }
}

class SearchValidationScreen extends StatefulWidget {
  const SearchValidationScreen({super.key});

  @override
  State<SearchValidationScreen> createState() => _SearchValidationScreenState();
}

class _SearchValidationScreenState extends State<SearchValidationScreen> {
  final TextEditingController _queryController = TextEditingController();
  final Highlighter _highlighter = const Highlighter();
  final List<SearchHit> _hits = <SearchHit>[];

  Searchlight? _db;
  DataSourceMode _mode = DataSourceMode.publicCorpus;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_runSearch);
    _loadMode(_mode);
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_runSearch)
      ..dispose();
    _db?.dispose();
    super.dispose();
  }

  Future<void> _loadMode(DataSourceMode mode) async {
    setState(() {
      _mode = mode;
      _loading = true;
      _error = null;
      _hits.clear();
    });

    final previousDb = _db;
    _db = null;
    await previousDb?.dispose();

    try {
      final loadedDb = await _loadDb(mode);
      if (!mounted) {
        await loadedDb.dispose();
        return;
      }
      setState(() {
        _db = loadedDb;
        _loading = false;
      });
      _runSearch();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<Searchlight> _loadDb(DataSourceMode mode) async {
    switch (mode) {
      case DataSourceMode.publicCorpus:
        final records = await _loadCorpusAsset('assets/search_corpus.json');
        return _buildDbFromRecords(records);
      case DataSourceMode.localCorpus:
        final records = await _loadCorpusAsset(
          'assets/local/generated_search_corpus.json',
        );
        if (records.isEmpty) {
          throw StateError(
            'Local corpus asset is not configured. '
            'Replace assets/local/generated_search_corpus.json '
            'with generated data.',
          );
        }
        return _buildDbFromRecords(records);
      case DataSourceMode.localSnapshot:
        final raw = await rootBundle.loadString(
          'assets/local/generated_search_snapshot.json',
        );
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) {
          throw const FormatException(
            'assets/local/generated_search_snapshot.json must be a JSON object.',
          );
        }
        if (json.isEmpty || !json.containsKey('documents')) {
          throw StateError(
            'Local snapshot asset is not configured. '
            'Replace assets/local/generated_search_snapshot.json '
            'with generated data.',
          );
        }
        return Searchlight.fromJson(json.cast<String, Object?>());
    }
  }

  Future<List<Map<String, Object?>>> _loadCorpusAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw FormatException('$path must be a JSON array.');
    }

    return decoded.map((dynamic entry) {
      if (entry is! Map<String, dynamic>) {
        throw FormatException('$path contains a non-object entry.');
      }
      return entry.cast<String, Object?>();
    }).toList();
  }

  Searchlight _buildDbFromRecords(List<Map<String, Object?>> records) {
    final db = Searchlight.create(
      schema: Schema({
        'url': const TypedField(SchemaType.string),
        'title': const TypedField(SchemaType.string),
        'content': const TypedField(SchemaType.string),
        'type': const TypedField(SchemaType.enumType),
        'group': const TypedField(SchemaType.enumType),
      }),
    );
    for (final record in records) {
      db.insert(record);
    }
    return db;
  }

  void _runSearch() {
    final db = _db;
    if (db == null) {
      return;
    }

    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(_hits.clear);
      return;
    }

    final result = db.search(
      term: query,
      properties: const ['title', 'content'],
      limit: 10,
    );
    setState(() {
      _hits
        ..clear()
        ..addAll(result.hits);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Searchlight Validation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text('Source:'),
                const SizedBox(width: 12),
                DropdownButton<DataSourceMode>(
                  value: _mode,
                  onChanged: (DataSourceMode? value) {
                    if (value != null) {
                      _loadMode(value);
                    }
                  },
                  items: const <DropdownMenuItem<DataSourceMode>>[
                    DropdownMenuItem<DataSourceMode>(
                      value: DataSourceMode.publicCorpus,
                      child: Text('Public fixture'),
                    ),
                    DropdownMenuItem<DataSourceMode>(
                      value: DataSourceMode.localCorpus,
                      child: Text('Local corpus asset'),
                    ),
                    DropdownMenuItem<DataSourceMode>(
                      value: DataSourceMode.localSnapshot,
                      child: Text('Local snapshot asset'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Search validation corpus...',
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const Text('Loading index...'),
            if (_error != null)
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _hits.length,
                itemBuilder: (BuildContext context, int index) {
                  final hit = _hits[index];
                  final title = hit.document.getString('title');
                  final content = hit.document.getString('content');
                  final query = _queryController.text.trim();

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hit.document.getString('url'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildExcerpt(content, query),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExcerpt(String text, String query) {
    final excerpt = _excerpt(text, 160);
    if (query.isEmpty) {
      return Text(
        excerpt,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    final result = _highlighter.highlight(excerpt, query);
    if (result.positions.isEmpty) {
      return Text(
        excerpt,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final position in result.positions) {
      if (position.start > cursor) {
        spans.add(TextSpan(text: excerpt.substring(cursor, position.start)));
      }
      spans.add(
        TextSpan(
          text: excerpt.substring(position.start, position.end),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = position.end;
    }
    if (cursor < excerpt.length) {
      spans.add(TextSpan(text: excerpt.substring(cursor)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _excerpt(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }
}
