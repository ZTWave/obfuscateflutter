# Dart Comment Cleaner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menu-driven, AST-safe cleaner that removes every Dart comment from every `.dart` file under a target Flutter project's `lib` directory.

**Architecture:** A focused `dart_comment_cleaner.dart` module will use Analyzer token streams to collect comment source ranges, rewrite ranges from right to left, validate that cleanup introduces no new parser diagnostics, and write per-run statistics to the shared HTML mapping. The CLI will expose the module as menu item `14` and run it last in the temporary-project `x` pipeline.

**Tech Stack:** Dart 3.2+, `package:analyzer` 6.4.1, `dart:io`, `package:path`, `package:test`, existing HTML mapping writer.

## Global Constraints

- Process only `<target-project>/lib/**/*.dart`.
- Process generated Dart files, including `.g.dart`, `.freezed.dart`, and `.gr.dart`.
- Remove `//`, `///`, `/* */`, and `/** */`, including Analyzer ignore directives.
- Preserve comment-like text inside normal, raw, interpolated, and triple-quoted strings.
- Do not create backups or a missing `lib` directory.
- Do not modify a file if cleanup introduces parser diagnostics not present in the original source.
- Continue after a per-file failure and report the failed relative path and reason.
- Run cleanup last in the `x` pipeline.

---

## File Structure

- Create `lib/dart_comment_cleaner.dart`: comment discovery, source rewrite, parser safety check, filesystem traversal, run result, logging, and mapping output.
- Create `test/dart_comment_cleaner_test.dart`: focused behavior and filesystem integration tests for the cleaner.
- Modify `bin/obfuscateflutter.dart`: menu `14`, wrapper function, and final `x` pipeline call.
- Modify `README.md`: menu, result table, behavior, scope, and caveats.

### Task 1: Analyzer-Based Comment Rewriter

**Files:**
- Create: `lib/dart_comment_cleaner.dart`
- Create: `test/dart_comment_cleaner_test.dart`

**Interfaces:**
- Consumes: `parseString({required String content, String? path, bool throwIfDiagnostics = true})`, `writeHtmlFeatureMapping(...)`, and a target Flutter project path.
- Produces: `DartCommentCleanupResult cleanDartComments(String projectPath)`.
- Produces: `DartCommentCleanupResult` with `scannedFiles`, `modifiedFiles`, `removedComments`, and `failedFiles`.
- Produces mapping feature id `dart_comment_cleanup` and title `Dart 源码注释清理`.

- [ ] **Step 1: Write failing tests for complete and safe comment removal**

Create `test/dart_comment_cleaner_test.dart` with a temporary project helper and tests that establish the public API:

```dart
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:obfuscateflutter/dart_comment_cleaner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mapping_test_utils.dart';

void main() {
  late Directory projectDir;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('dart_comment_cleaner_');
    Directory(p.join(projectDir.path, 'lib')).createSync();
  });

  tearDown(() {
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }
  });

  test('removes every comment kind and preserves comment-like strings', () {
    final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
      ..writeAsStringSync(r'''
/// Library docs.
void main() {
  // line
  final url = 'https://example.com/a//b';
  final raw = r'/* raw */';
  final triple = """// text
/* text */""";
  print(url); /* block */
  print(raw); /** docs */
  print(triple);
}
''');

    final result = cleanDartComments(projectDir.path);
    final updated = file.readAsStringSync();

    expect(result.scannedFiles, 1);
    expect(result.modifiedFiles, 1);
    expect(result.removedComments, 4);
    expect(result.failedFiles, isEmpty);
    expect(updated, isNot(contains('Library docs')));
    expect(updated, contains("'https://example.com/a//b'"));
    expect(updated, contains("r'/* raw */'"));
    expect(updated, contains('"""// text\n/* text */"""'));
    expect(parseString(content: updated).errors, isEmpty);
  });

  test('keeps token boundaries valid when an inline block comment is removed', () {
    final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
      ..writeAsStringSync('''
void main() {
  final value = 1/* separator */is int;
  print(value);
}
''');

    cleanDartComments(projectDir.path);
    final updated = file.readAsStringSync();

    expect(updated, contains('1 is int'));
    expect(parseString(content: updated).errors, isEmpty);
  });
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
dart test test/dart_comment_cleaner_test.dart
```

Expected: FAIL because `package:obfuscateflutter/dart_comment_cleaner.dart` and `cleanDartComments` do not exist.

- [ ] **Step 3: Implement the token-range rewriter and public result**

Create `lib/dart_comment_cleaner.dart`. Use these public types:

```dart
class DartCommentCleanupFailure {
  const DartCommentCleanupFailure({
    required this.path,
    required this.reason,
  });

  final String path;
  final String reason;

  Map<String, String> toJson() => {
        'path': path,
        'reason': reason,
      };
}

class DartCommentCleanupResult {
  const DartCommentCleanupResult({
    required this.scannedFiles,
    required this.modifiedFiles,
    required this.removedComments,
    required this.failedFiles,
  });

  final int scannedFiles;
  final int modifiedFiles;
  final int removedComments;
  final List<DartCommentCleanupFailure> failedFiles;
}

DartCommentCleanupResult cleanDartComments(String projectPath)
```

Implementation requirements:

1. Resolve `Directory(p.join(projectPath, 'lib'))`; throw `StateError` if it does not exist.
2. Enumerate recursively, keep `File` entries ending in `.dart`, and sort by path for deterministic mappings.
3. Parse each source with `parseString(content: source, path: file.path, throwIfDiagnostics: false)`.
4. Traverse from `parseResult.unit.beginToken` through `Token.next`, including EOF. For each code token, traverse `token.precedingComments` through each `CommentToken.next` and collect unique `(offset, length, lexeme)` ranges.
5. Replace ranges from highest offset to lowest offset.
6. For block comments, replace every non-newline character with nothing while retaining each `\r\n`, `\r`, or `\n`; if no newline exists, use one space. Replace line-comment lexemes with an empty string because their line terminator is outside the token.
7. Compare parser-diagnostic signatures before and after cleanup as multisets of `errorCode.name` plus `message`. If the updated multiset contains a diagnostic occurrence not present in the original multiset, fail the file without writing it.
8. Write only when the rewritten source differs from the original.
9. Catch per-file `Object`/`StackTrace`, add `DartCommentCleanupFailure(path: p.relative(file.path, from: projectPath), reason: '$error')`, and continue.
10. Write the mapping even when no files change:

```dart
final mapping = {
  'generated_at': DateTime.now().toIso8601String(),
  'summary': {
    'scanned_files': scannedFiles,
    'modified_files': modifiedFiles,
    'removed_comments': removedComments,
    'failed_files': failedFiles.length,
  },
  'scanned_files': scannedFiles,
  'modified_files': modifiedFiles,
  'removed_comments': removedComments,
  'failed_files': failedFiles.map((failure) => failure.toJson()).toList(),
};
writeHtmlFeatureMapping(
  projectPath: projectPath,
  featureId: 'dart_comment_cleanup',
  featureTitle: 'Dart 源码注释清理',
  mapping: mapping,
);
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
dart test test/dart_comment_cleaner_test.dart
```

Expected: both tests PASS.

- [ ] **Step 5: Add integration tests for scope, generated files, idempotency, failures, and mapping**

Append tests with these assertions:

```dart
test('processes generated files under lib but ignores dart files outside lib',
    () {
  final generated = File(p.join(projectDir.path, 'lib', 'model.g.dart'))
    ..writeAsStringSync('const value = 1; // generated\n');
  final outside = File(p.join(projectDir.path, 'tool.dart'))
    ..writeAsStringSync('const value = 1; // outside\n');

  final result = cleanDartComments(projectDir.path);

  expect(generated.readAsStringSync(), isNot(contains('generated')));
  expect(outside.readAsStringSync(), contains('// outside'));
  expect(result.scannedFiles, 1);
  expect(result.removedComments, 1);
});

test('is idempotent and records zero modifications on the second run', () {
  final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
    ..writeAsStringSync('void main() {} // remove\n');

  cleanDartComments(projectDir.path);
  final firstContent = file.readAsStringSync();
  final firstModified = file.lastModifiedSync();
  sleep(const Duration(milliseconds: 20));
  final second = cleanDartComments(projectDir.path);

  expect(file.readAsStringSync(), firstContent);
  expect(file.lastModifiedSync(), firstModified);
  expect(second.modifiedFiles, 0);
  expect(second.removedComments, 0);
});

test('continues after a file cannot be read and writes mapping statistics', () {
  final good = File(p.join(projectDir.path, 'lib', 'good.dart'))
    ..writeAsStringSync('const good = true; // remove\n');
  final bad = File(p.join(projectDir.path, 'lib', 'bad.dart'))
    ..writeAsBytesSync([0xFF]);

  final result = cleanDartComments(projectDir.path);
  final mapping =
      readHtmlFeatureMapping(projectDir, 'dart_comment_cleanup');

  expect(good.readAsStringSync(), isNot(contains('remove')));
  expect(result.failedFiles, hasLength(1));
  expect(mapping['scanned_files'], 2);
  expect(mapping['modified_files'], 1);
  expect(mapping['removed_comments'], 1);
  expect(mapping['failed_files'], hasLength(1));
});
```

The invalid UTF-8 byte forces `readAsStringSync()` to fail consistently without
depending on platform permission behavior.

- [ ] **Step 6: Run all cleaner tests**

Run:

```bash
dart test test/dart_comment_cleaner_test.dart
```

Expected: PASS with all cleaner tests green and no warnings.

- [ ] **Step 7: Commit the cleaner**

```bash
git add lib/dart_comment_cleaner.dart test/dart_comment_cleaner_test.dart
git commit -m "feat: add Dart comment cleaner"
```

### Task 2: CLI and Temporary Pipeline Integration

**Files:**
- Modify: `bin/obfuscateflutter.dart`
- Test: `test/dart_comment_cleaner_test.dart`

**Interfaces:**
- Consumes: `DartCommentCleanupResult cleanDartComments(String projectPath)` from Task 1.
- Produces: menu selection `14` and `_runDartCommentCleanup(String projectPath)`.
- Produces: a final cleanup call in `_runAllObfuscationSteps`.

- [ ] **Step 1: Write a failing source-level CLI integration test**

Append:

```dart
test('CLI exposes menu 14 and runs cleanup last in the x pipeline', () {
  final cli = File(p.join(Directory.current.path, 'bin', 'obfuscateflutter.dart'))
      .readAsStringSync();

  expect(cli, contains('14.清理 Dart 源码注释'));
  expect(cli, contains('case "14":'));
  expect(cli, contains('_runDartCommentCleanup(projectPath);'));

  final pipelineStart = cli.indexOf(
    'Future<void> _runAllObfuscationSteps(String projectPath)',
  );
  final pipelineEnd = cli.indexOf(
    'Future<void> _runIosNoiseObfuscation',
    pipelineStart,
  );
  final pipeline = cli.substring(pipelineStart, pipelineEnd);
  expect(
    pipeline.lastIndexOf('_runDartCommentCleanup(projectPath);'),
    greaterThan(pipeline.lastIndexOf('_runIosFunctionRename(projectPath)')),
  );
});
```

- [ ] **Step 2: Run the integration test and verify RED**

Run:

```bash
dart test test/dart_comment_cleaner_test.dart -n "CLI exposes"
```

Expected: FAIL because menu item `14` is absent.

- [ ] **Step 3: Wire the cleaner into the CLI**

Modify `bin/obfuscateflutter.dart`:

```dart
import 'package:obfuscateflutter/dart_comment_cleaner.dart';
```

Add to the menu:

```text
14.清理 Dart 源码注释
```

Add to the switch:

```dart
case "14":
  {
    _runDartCommentCleanup(projectPath);
    break;
  }
```

Add the wrapper:

```dart
void _runDartCommentCleanup(String projectPath) {
  print('do dart comment cleanup');
  cleanDartComments(projectPath);
  print('do dart comment cleanup finished');
}
```

Call `_runDartCommentCleanup(projectPath);` after `_runIosFunctionRename(projectPath)` in `_runAllObfuscationSteps`.

- [ ] **Step 4: Run the integration test and verify GREEN**

Run:

```bash
dart test test/dart_comment_cleaner_test.dart -n "CLI exposes"
```

Expected: PASS.

- [ ] **Step 5: Run static analysis and focused tests**

Run:

```bash
dart analyze lib/dart_comment_cleaner.dart bin/obfuscateflutter.dart test/dart_comment_cleaner_test.dart
dart test test/dart_comment_cleaner_test.dart
```

Expected: analysis reports `No issues found!`; tests PASS.

- [ ] **Step 6: Commit CLI integration**

```bash
git add bin/obfuscateflutter.dart test/dart_comment_cleaner_test.dart
git commit -m "feat: expose Dart comment cleanup task"
```

### Task 3: User Documentation and Full Verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the finalized menu number, scope, mapping feature, and pipeline order.
- Produces: user-facing documentation matching implemented behavior.

- [ ] **Step 1: Update README menu and feature table**

Add menu item:

```text
14.清理 Dart 源码注释
```

Add a feature-table row stating that all comments in `lib/**/*.dart`, including generated files and Analyzer ignore directives, are removed using Analyzer token scanning.

- [ ] **Step 2: Add the detailed feature section**

Document:

```markdown
### 14. 清理 Dart 源码注释

递归扫描目标项目 `lib/**/*.dart`，删除 `//`、`///`、`/* */` 和 `/** */`
注释。生成文件也会处理，字符串和多行字符串中的注释符号不会被误删。

结果：

- 原地修改包含注释的 Dart 文件。
- 保留必要的空格和换行，避免相邻 token 粘连。
- 写入 `obfuscation_mapping.html` 的“Dart 源码注释清理”区块。
- 单个文件失败时继续处理其他文件，并在 mapping 中记录失败路径和原因。

注意：`// ignore` 和 `// ignore_for_file` 也会删除；该功能不处理 `lib`
以外的文件，也不生成备份。
```

Update the `x` description to state that comment cleanup runs last.

- [ ] **Step 3: Format and verify the complete change**

Run:

```bash
dart format --output=none --set-exit-if-changed lib/dart_comment_cleaner.dart bin/obfuscateflutter.dart test/dart_comment_cleaner_test.dart
dart analyze lib/dart_comment_cleaner.dart bin/obfuscateflutter.dart test/dart_comment_cleaner_test.dart
dart test test/dart_comment_cleaner_test.dart
dart test
git diff --check
```

Expected: formatter exits `0`, analysis reports no issues, focused and full tests PASS, and `git diff --check` emits no output.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md
git commit -m "docs: document Dart comment cleanup"
```

- [ ] **Step 5: Verify repository state**

Run:

```bash
git status --short --branch
git log --oneline -5
```

Expected: feature files are committed; the pre-existing `.claude/settings.local.json` deletion remains untouched.
