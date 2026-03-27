import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:searchlight/searchlight.dart';
import 'package:searchlight_example/src/excerpt_spans.dart';
import 'package:searchlight_example/src/folder_source_loader.dart';
import 'package:searchlight_example/src/loaded_validation_source.dart';
import 'package:searchlight_example/src/search_index_service.dart';
import 'package:searchlight_example/src/search_result_item.dart';
import 'package:searchlight_example/src/validation_record.dart';

void main() {
  runApp(const SearchValidationApp());
}

enum ValidationSourceMode {
  publicFixture,
  desktopFolder,
  localCorpus,
  localSnapshot,
}

class SearchValidationApp extends StatelessWidget {
  const SearchValidationApp({
    super.key,
    this.bundle,
    this.folderSourceLoader,
    this.supportsDesktopFolderSource,
    this.pickDirectory,
  });

  final AssetBundle? bundle;
  final FolderSourceLoader? folderSourceLoader;
  final bool? supportsDesktopFolderSource;
  final Future<String?> Function()? pickDirectory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5B3A)),
        useMaterial3: true,
      ),
      home: SearchValidationScreen(
        bundle: bundle ?? rootBundle,
        folderSourceLoader: folderSourceLoader ?? createFolderSourceLoader(),
        supportsDesktopFolderSource:
            supportsDesktopFolderSource ??
            _defaultSupportsDesktopFolderSource(),
        pickDirectory: pickDirectory ?? getDirectoryPath,
      ),
    );
  }

  bool _defaultSupportsDesktopFolderSource() {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }
}

class SearchValidationScreen extends StatefulWidget {
  const SearchValidationScreen({
    required this.bundle,
    required this.folderSourceLoader,
    required this.supportsDesktopFolderSource,
    required this.pickDirectory,
    super.key,
  });

  final AssetBundle bundle;
  final FolderSourceLoader folderSourceLoader;
  final bool supportsDesktopFolderSource;
  final Future<String?> Function() pickDirectory;

  @override
  State<SearchValidationScreen> createState() => _SearchValidationScreenState();
}

class _SearchValidationScreenState extends State<SearchValidationScreen> {
  final TextEditingController _queryController = TextEditingController();
  final Highlighter _highlighter = const Highlighter();
  final SearchIndexService _searchIndexService = const SearchIndexService();

  LoadedValidationSource? _source;
  ValidationSourceMode _mode = ValidationSourceMode.publicFixture;
  List<SearchResultItem> _results = const [];
  ValidationRecord? _selectedRecord;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_runSearch);
    _loadAssetMode(_mode);
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_runSearch)
      ..dispose();
    _source?.dispose();
    super.dispose();
  }

  Future<void> _chooseFolder() async {
    if (!widget.supportsDesktopFolderSource) {
      _showMessage(
        'Desktop folder indexing is only available in desktop builds.',
      );
      return;
    }

    final path = await widget.pickDirectory();
    if (path == null || path.isEmpty) {
      return;
    }

    await _loadFolder(path);
  }

  Future<void> _onModeChanged(ValidationSourceMode mode) async {
    switch (mode) {
      case ValidationSourceMode.publicFixture:
      case ValidationSourceMode.localCorpus:
      case ValidationSourceMode.localSnapshot:
        await _loadAssetMode(mode);
      case ValidationSourceMode.desktopFolder:
        final previous = _source;
        _source = null;
        await previous?.dispose();
        setState(() {
          _mode = mode;
          _loading = false;
          _error = null;
          _results = const [];
          _selectedRecord = null;
        });
    }
  }

  Future<void> _loadAssetMode(ValidationSourceMode mode) async {
    setState(() {
      _mode = mode;
      _loading = true;
      _error = null;
      _results = const [];
      _selectedRecord = null;
    });

    final previous = _source;
    _source = null;
    await previous?.dispose();

    try {
      final nextSource = await _createAssetSource(mode);
      if (!mounted) {
        await nextSource.dispose();
        return;
      }
      _applySource(nextSource, mode);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadFolder(String rootPath) async {
    setState(() {
      _mode = ValidationSourceMode.desktopFolder;
      _loading = true;
      _error = null;
      _results = const [];
      _selectedRecord = null;
    });

    final previous = _source;
    _source = null;
    await previous?.dispose();

    try {
      final loadResult = await widget.folderSourceLoader.load(rootPath);
      final nextSource = _searchIndexService.buildFromRecords(
        records: loadResult.records,
        label: loadResult.rootPath,
        discoveredCount: loadResult.discoveredMarkdownFiles,
        issues: loadResult.issues,
      );
      if (!mounted) {
        await nextSource.dispose();
        return;
      }
      _applySource(nextSource, ValidationSourceMode.desktopFolder);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<LoadedValidationSource> _createAssetSource(
    ValidationSourceMode mode,
  ) async {
    switch (mode) {
      case ValidationSourceMode.publicFixture:
        final records = await _loadRecordsAsset('assets/search_corpus.json');
        return _searchIndexService.buildFromRecords(
          records: records,
          label: 'Public fixture',
          discoveredCount: records.length,
        );
      case ValidationSourceMode.localCorpus:
        final records = await _loadRecordsAsset(
          'assets/local/generated_search_corpus.json',
        );
        if (records.isEmpty) {
          throw StateError(
            'Local corpus asset is not configured. Replace '
            'assets/local/generated_search_corpus.json with generated data.',
          );
        }
        return _searchIndexService.buildFromRecords(
          records: records,
          label: 'Local corpus asset',
          discoveredCount: records.length,
        );
      case ValidationSourceMode.localSnapshot:
        final raw = await widget.bundle.loadString(
          'assets/local/generated_search_snapshot.json',
        );
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'assets/local/generated_search_snapshot.json must be a JSON object.',
          );
        }
        if (decoded.isEmpty || !decoded.containsKey('documents')) {
          throw StateError(
            'Local snapshot asset is not configured. Replace '
            'assets/local/generated_search_snapshot.json with generated data.',
          );
        }
        return _searchIndexService.restoreFromSnapshot(
          json: decoded.cast<String, Object?>(),
          label: 'Local snapshot asset',
        );
      case ValidationSourceMode.desktopFolder:
        throw StateError('Desktop folder mode is not asset-backed.');
    }
  }

  Future<List<ValidationRecord>> _loadRecordsAsset(String path) async {
    final raw = await widget.bundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw FormatException('$path must be a JSON array.');
    }

    return decoded
        .map((dynamic entry) {
          if (entry is! Map<String, dynamic>) {
            throw FormatException('$path contains a non-object entry.');
          }
          return ValidationRecord.fromMap(entry.cast<String, Object?>());
        })
        .toList(growable: false);
  }

  void _applySource(LoadedValidationSource source, ValidationSourceMode mode) {
    final results = _searchIndexService.search(source, _queryController.text);
    setState(() {
      _source = source;
      _mode = mode;
      _loading = false;
      _error = null;
      _results = results;
      _selectedRecord = results.isEmpty ? null : results.first.record;
    });
  }

  void _runSearch() {
    final source = _source;
    if (source == null) {
      return;
    }

    final nextResults = _searchIndexService.search(
      source,
      _queryController.text,
    );
    final selectedId = _selectedRecord?.id;
    ValidationRecord? nextSelected;
    for (final result in nextResults) {
      if (result.record.id == selectedId) {
        nextSelected = result.record;
        break;
      }
    }
    nextSelected ??= nextResults.isEmpty ? null : nextResults.first.record;

    setState(() {
      _results = nextResults;
      _selectedRecord = nextSelected;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Searchlight Validation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<ValidationSourceMode>(
                      value: _mode,
                      onChanged: (value) {
                        if (value != null) {
                          _onModeChanged(value);
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ValidationSourceMode.publicFixture,
                          child: Text('Public fixture'),
                        ),
                        DropdownMenuItem(
                          value: ValidationSourceMode.desktopFolder,
                          child: Text('Desktop folder'),
                        ),
                        DropdownMenuItem(
                          value: ValidationSourceMode.localCorpus,
                          child: Text('Local corpus asset'),
                        ),
                        DropdownMenuItem(
                          value: ValidationSourceMode.localSnapshot,
                          child: Text('Local snapshot asset'),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: _chooseFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose Folder'),
                    ),
                    _MetricChip(
                      label: 'Discovered',
                      value: '${source?.discoveredCount ?? 0}',
                    ),
                    _MetricChip(
                      label: 'Indexed',
                      value: '${source?.indexedCount ?? 0}',
                    ),
                    _MetricChip(
                      label: 'Issues',
                      value: '${source?.issues.length ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  source?.label ??
                      (_mode == ValidationSourceMode.desktopFolder
                          ? 'Choose a folder to build a live markdown index.'
                          : 'Loading source...'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Search title and content...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_error case final message?) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      Expanded(child: _buildResultsPane()),
                      const Divider(height: 1),
                      Expanded(child: _buildViewerPane()),
                    ],
                  );
                }

                return Row(
                  children: [
                    SizedBox(width: 380, child: _buildResultsPane()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildViewerPane()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPane() {
    final source = _source;
    if (_loading) {
      return const Center(child: Text('Loading source...'));
    }
    if (_mode == ValidationSourceMode.desktopFolder && source == null) {
      return const Center(
        child: Text('Choose a folder to build a live markdown index.'),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text('No documents matched the current query.'),
      );
    }

    return Column(
      children: [
        if (source != null && source.issues.isNotEmpty)
          ExpansionTile(
            title: Text('Load issues (${source.issues.length})'),
            children: source.issues
                .map(
                  (issue) => ListTile(
                    dense: true,
                    title: Text(issue.path),
                    subtitle: Text(issue.message),
                  ),
                )
                .toList(growable: false),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = _results[index];
              final query = _queryController.text.trim();
              final excerpt = _excerptFor(result.record.content);
              final positions = query.isEmpty
                  ? const <HighlightPosition>[]
                  : _highlighter.highlight(excerpt, query).positions;

              return ListTile(
                selected: _selectedRecord?.id == result.record.id,
                title: Text(result.record.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.record.pathLabel),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: buildHighlightedExcerptSpans(
                          excerpt,
                          positions,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: Text(result.score.toStringAsFixed(2)),
                onTap: () {
                  setState(() {
                    _selectedRecord = result.record;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildViewerPane() {
    final record = _selectedRecord;
    if (_mode == ValidationSourceMode.desktopFolder && _source == null) {
      return const Center(
        child: Text('Choose a folder and inspect indexed markdown here.'),
      );
    }
    if (record == null) {
      return const Center(
        child: Text('Select a result to inspect the indexed document.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              SelectableText(record.pathLabel),
              if (record.sourcePath case final sourcePath?) ...[
                const SizedBox(height: 4),
                SelectableText(
                  sourcePath,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Markdown(
            data: record.displayBody,
            padding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  String _excerptFor(String content) {
    const maxLength = 180;
    if (content.length <= maxLength) {
      return content;
    }
    return '${content.substring(0, maxLength).trimRight()}...';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}
