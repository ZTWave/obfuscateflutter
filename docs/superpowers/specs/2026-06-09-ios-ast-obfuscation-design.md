# iOS AST Obfuscation Design

## Goal

Add an iOS obfuscation feature for Flutter projects. The feature scans the
`ios` directory, reads Objective-C and Swift files through native AST tools,
injects useless code from Objective-C and Swift template groups, and applies
conservative structure changes without changing business behavior.

The first version prioritizes compile safety and traceability over aggressive
rewrites.

## Entry Point

Add a new menu item to `bin/obfuscateflutter.dart`:

```text
10.iOS Object-C/Swift AST 混淆
```

The entry point calls:

```dart
runIosNoiseObfuscation(projectPath);
```

Implementation lives in a new `lib/ios_noise_obfuscator.dart` module, matching
the style of `lib/android_noise_generator.dart` and
`lib/dart_noise_obfuscator.dart`.

## Configuration

Use the existing `obfuscate_dart_noise.json` file and add an `iosNoise` section.
The tool reads the project-level config first, then falls back to the tool
default config.

Default shape:

```json
{
  "iosNoise": {
    "enabled": true,
    "targetRatio": 0.4,
    "maxTargetLines": 20000,
    "maxInsertionsPerFile": 20,
    "astFallback": "skip",
    "skipFiles": [
      "**/Pods/**",
      "**/.symlinks/**",
      "**/Flutter/**",
      "**/GeneratedPluginRegistrant.*",
      "**/build/**",
      "**/*.pbobjc.*"
    ],
    "templateGroups": {
      "objectiveC": [
        "oc_string_table",
        "oc_numeric_fold",
        "oc_guarded_branch"
      ],
      "swift": [
        "swift_string_table",
        "swift_numeric_fold",
        "swift_guarded_branch"
      ]
    },
    "stringTemplates": [
      {
        "id": "session_word_seed",
        "value": "session.{{word}}.{{seed}}"
      },
      {
        "id": "trace_context",
        "value": "trace.{{fileName}}.{{methodName}}.{{index}}"
      }
    ]
  }
}
```

Field meanings:

- `enabled`: disable the feature without removing config.
- `targetRatio`: target added non-empty lines relative to processable source
  lines.
- `maxTargetLines`: hard cap for added lines.
- `maxInsertionsPerFile`: safety cap per file.
- `astFallback`: `skip` by default. Later can support `lightweight` if needed.
- `skipFiles`: glob-style paths relative to the project root.
- `templateGroups.objectiveC`: Objective-C templates to choose from.
- `templateGroups.swift`: Swift templates to choose from.
- `stringTemplates`: readable text templates rendered into useless code.

## File Scope

Process:

- `ios/**/*.m`
- `ios/**/*.mm`
- `ios/**/*.swift`

Read-only AST classification, but no code injection by default:

- `ios/**/*.h`

Skip by default:

- `ios/Pods/**`
- `ios/.symlinks/**`
- `ios/Flutter/**`
- `ios/**/GeneratedPluginRegistrant.*`
- build output directories
- protobuf generated Objective-C files such as `*.pbobjc.*`

The first implementation does not rename iOS files, classes, methods, resources,
or public symbols. That keeps Xcode project references, Swift symbol visibility,
Objective-C selector behavior, and Flutter plugin registration stable.

## AST Reading

Objective-C:

```bash
xcrun clang -x objective-c -fsyntax-only -Xclang -ast-dump=json <file>
```

Objective-C++:

```bash
xcrun clang -x objective-c++ -fsyntax-only -Xclang -ast-dump=json <file>
```

Swift:

```bash
xcrun swiftc -dump-ast -parse <file>
```

The tool records each command and exit result in the mapping document. If AST
reading fails, the file is skipped and the skip reason is recorded. The first
version does not guess unsafe insertions when AST is unavailable.

## AST Model

Create a language-neutral internal model:

```dart
class IosAstFile {
  String path;
  IosLanguage language;
  List<IosInsertionTarget> targets;
  List<IosAstWarning> warnings;
}

class IosInsertionTarget {
  String containerName;
  String methodName;
  int bodyStartOffset;
  int bodyEndOffset;
  int insertionOffset;
  bool isStaticLike;
}
```

For Objective-C, targets come from implementation method declarations with
source ranges inside `.m` or `.mm` files.

For Swift, targets come from function, initializer, and method bodies that have
clear source ranges and block bodies.

## Safe Insertion Rules

Only insert inside method or function bodies.

Allowed locations:

- At the start of a non-empty body, after the opening brace.
- Before a final `return` only when the return offset is reliably identified.

Disallowed locations:

- Headers and public declarations.
- Method or function signatures.
- Swift protocol requirements.
- Swift computed property accessors in the first version.
- Objective-C macro bodies.
- Any body that contains existing `obfuscateflutter: ios-noise` markers.
- Any AST range that cannot be mapped back to the source file.

All replacements are applied from the end of the file to the beginning so source
offsets remain valid.

## Templates

Templates are built in first, with config selecting ids and weights. Custom iOS
templates can be added later after the safety constraints are proven.

Objective-C templates:

- `oc_string_table`: local `NSArray` and `NSDictionary` string references.
- `oc_numeric_fold`: deterministic local integer folding.
- `oc_guarded_branch`: a branch guarded by a local condition that does not
  affect method outputs.

Swift templates:

- `swift_string_table`: local array and dictionary string references.
- `swift_numeric_fold`: deterministic local integer folding.
- `swift_guarded_branch`: a branch guarded by a local condition that does not
  affect method outputs.

Each inserted block is wrapped with markers:

```text
// obfuscateflutter: ios-noise start <id>
...
// obfuscateflutter: ios-noise end <id>
```

Markers make repeat execution idempotent at the method body level.

## Structure Changes

The first version performs only local, semantics-preserving structure changes:

- Split generated garbage calculations into multiple local statements.
- Wrap generated garbage statements in deterministic guard branches.
- Mix string table references with numeric folding in generated code.

It does not move business statements, extract helper methods from business code,
change selectors, change Swift access control, or reorder existing statements.

## Mapping Document

Write:

```text
ios_noise_mapping_<timestamp>.json
```

The document includes:

- generation timestamp
- config source and resolved config
- AST tools used
- files scanned
- files touched
- insertions with file, language, container, method, template id, offset, and
  added lines
- skipped files with reasons
- AST warnings
- summary counts

This mirrors the traceability style of existing Dart and Android mapping files.

## Error Handling

Hard errors:

- project directory does not exist
- `ios` directory does not exist
- invalid `iosNoise` config shape

Soft skips:

- AST command unavailable or failed for one file
- unsupported file extension
- no safe insertion targets
- generated or skipped path
- ambiguous source ranges

Soft skips are reported in the mapping file and console summary.

## Testing

Add `test/ios_noise_obfuscator_test.dart` with temp project fixtures.

Core tests:

- Objective-C method body receives marked template code.
- Swift method body receives marked template code.
- headers are not modified.
- skipped paths are not modified.
- repeated runs do not duplicate markers in the same method.
- invalid config throws a clear `StateError`.
- mapping document records touched files, skipped files, templates, and AST
  command status.

Tests should avoid requiring a complete Xcode project. For AST-dependent tests,
use small standalone `.m` and `.swift` files that `xcrun clang` and
`xcrun swiftc` can parse on macOS. If the toolchain is missing, tests can skip
with a clear reason.

## Acceptance Criteria

- Menu item 10 runs the iOS obfuscation feature.
- Objective-C and Swift files are read through AST commands before modification.
- Safe method/function bodies receive garbage code from the correct language
  template group.
- Existing business statements, signatures, class names, file names, and public
  APIs are not changed.
- Re-running the feature does not repeatedly inject into already marked bodies.
- A mapping document is written for every run.
- Unit tests cover Objective-C, Swift, skip rules, idempotence, config parsing,
  and mapping output.
