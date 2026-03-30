# Searchlight Pub.dev Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prepare `searchlight` for pub.dev by aligning publish-facing metadata, README badges, and linked docs with the current package surface, then verify the package with publish dry-run checks.

**Architecture:** Keep the change set small and publish-focused. Update the root package metadata and README first, then refresh only the linked docs that materially affect pub.dev users, and finally run validation commands to catch any remaining issues.

**Tech Stack:** Dart package metadata, Markdown docs, pub.dev publish dry-run, Dart analyzer

---

### Task 1: Audit Publish-Facing Surface

**Files:**
- Modify: `README.md`
- Modify: `pubspec.yaml`
- Review: `doc/README.md`
- Review: `doc/app-integration.md`
- Review: `doc/validation-workflow.md`

**Step 1: Review package metadata and top README badges**

Read the current badge row, package description, links, and topics.

**Step 2: Compare against reference package presentation**

Read `../icloud_storage_plus/README.md` and capture which badges and wording
patterns should carry over.

**Step 3: Identify only publish-facing drift**

List mismatches such as outdated links, missing DeepWiki/publisher badges, or
docs that no longer match the current package surface.

### Task 2: Update Metadata And Docs

**Files:**
- Modify: `README.md`
- Modify: `pubspec.yaml`
- Modify: `doc/README.md` if needed
- Modify: `doc/app-integration.md` if needed
- Modify: `doc/validation-workflow.md` if needed

**Step 1: Update top README badges**

Add the `Ask DeepWiki` badge and the same publisher badge style used by
`icloud_storage_plus`, while keeping badges appropriate for a pure Dart package.

**Step 2: Tighten `pubspec.yaml` metadata**

Fix any publish-facing metadata issues found during the audit, including bad
documentation links or weak topics.

**Step 3: Refresh linked docs**

Make only the documentation changes needed so linked docs and setup guidance are
accurate for the current package and validation workflow.

### Task 3: Validate Publish Readiness

**Files:**
- Review only: analyzer and publish outputs

**Step 1: Resolve package dependencies**

Run: `dart pub get`

Expected: dependencies resolve successfully.

**Step 2: Run analyzer**

Run: `dart analyze`

Expected: no analyzer errors in the package.

**Step 3: Run publish dry-run**

Run: `dart pub publish --dry-run`

Expected: package validates successfully, with warnings handled if they are part
of the publish-facing scope.

**Step 4: Request review**

Use review agents to check that publish-facing docs are accurate and that the
README/pubspec presentation is consistent with the intended release posture.
