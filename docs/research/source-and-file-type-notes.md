# Source and File-Type Notes

Searchlight core indexes records and snapshots. It does not currently expose a
public file-parser layer.

Working rules:

- Treat file support as an extraction concern, not a core-engine concern.
- Document example-app support separately from core-package support.
- Avoid claiming that a file type is "supported" unless the package ships a
  parser or adapter for it.

Current state in this repository:

- core package: record insertion and snapshot restore
- validation example: live `.md` folder loading plus JSON corpus/snapshot
  assets
- no built-in public HTML, PDF, CSV, or XML parser

Behavioral note:

- raw HTML inserted into a searchable string field is tokenized as text,
  including markup tokens
- raw Markdown inserted into a searchable string field is tokenized as text,
  including link-destination fragments

Executable coverage:

- `test/integration/source_format_behavior_test.dart`
