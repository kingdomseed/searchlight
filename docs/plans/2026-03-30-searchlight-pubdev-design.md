# Searchlight Pub.dev Readiness Design

## Goal

Prepare `searchlight` for an initial pub.dev publish pass without cutting the
release yet. This pass should tighten package metadata, align the top README
badge row with the style used in `icloud_storage_plus` where it still fits a
pure Dart package, and refresh publish-facing docs so the package description,
README, and linked docs accurately describe the current API surface.

## Scope

- Update top-of-README badges to include the `Ask DeepWiki` badge and the same
  publisher presentation used in `icloud_storage_plus`.
- Review and fix publish-facing `pubspec.yaml` metadata such as description,
  documentation URL, and topics if needed.
- Review package-facing docs for obvious drift against the current package
  surface, especially `README.md`, `doc/README.md`, `doc/app-integration.md`,
  and `doc/validation-workflow.md`.
- Validate with package analysis and `dart pub publish --dry-run`.

## Non-Goals

- No version bump or release section cut in `CHANGELOG.md` yet.
- No repository restructuring.
- No new feature work beyond documentation or publish metadata cleanup.

## Approach Options

### Option 1: Minimal publish-readiness pass

Edit only `README.md` and `pubspec.yaml`, then validate.

Pros: smallest change set.
Cons: risks leaving stale supporting docs and pub.dev quality warnings.

### Option 2: Recommended targeted publish pass

Edit `README.md`, `pubspec.yaml`, and the small set of linked docs that pub.dev
users are likely to read first. Validate with analyzer and publish dry run.

Pros: good publish readiness without broad repo churn.
Cons: slightly more review work.

### Option 3: Full release-prep pass

Do the targeted publish pass and also finalize version/changelog decisions.

Pros: one-step release prep.
Cons: mixes publish readiness with release management.

## Chosen Design

Use Option 2. The work will stay focused on the package's publish surface:
metadata, README badges, and linked docs. Review agents will be used to catch
documentation drift and compare badge/metadata presentation against
`icloud_storage_plus`. Validation will drive any final adjustments before
stopping.
