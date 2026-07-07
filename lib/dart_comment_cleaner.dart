import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

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

class DartCommentFormatFailure {
  const DartCommentFormatFailure({
    required this.path,
    required this.exitCode,
    required this.message,
  });

  final String path;
  final int exitCode;
  final String message;

  Map<String, Object> toJson() => {
        'path': path,
        'exit_code': exitCode,
        'message': message,
      };
}

class DartCommentCleanupResult {
  const DartCommentCleanupResult({
    required this.scannedFiles,
    required this.modifiedFiles,
    required this.removedComments,
    required this.removedBlankLines,
    required this.formattedFiles,
    required this.formatFailedFiles,
    required this.failedFiles,
  });

  final int scannedFiles;
  final int modifiedFiles;
  final int removedComments;
  final int removedBlankLines;
  final int formattedFiles;
  final List<DartCommentFormatFailure> formatFailedFiles;
  final List<DartCommentCleanupFailure> failedFiles;
}

class _CommentRange {
  const _CommentRange({
    required this.offset,
    required this.length,
    required this.lexeme,
  });

  final int offset;
  final int length;
  final String lexeme;
}

class _BlankLineCleanupResult {
  const _BlankLineCleanupResult({
    required this.source,
    required this.removedLines,
  });

  final String source;
  final int removedLines;
}

DartCommentCleanupResult cleanDartComments(String projectPath) {
  final libDirectory = Directory(p.join(projectPath, 'lib'));
  if (!libDirectory.existsSync()) {
    throw StateError('lib directory not found in $projectPath');
  }

  final files = libDirectory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  var modifiedFiles = 0;
  var removedComments = 0;
  var removedBlankLines = 0;
  final failedFiles = <DartCommentCleanupFailure>[];

  for (final file in files) {
    try {
      final source = file.readAsStringSync();
      final originalParse = parseString(
        content: source,
        path: file.path,
        throwIfDiagnostics: false,
      );
      final comments = _collectCommentRanges(originalParse);
      final withoutComments =
          comments.isEmpty ? source : _removeCommentRanges(source, comments);
      final blankLineCleanup = _removeCodeBlankLines(withoutComments);
      final updated = blankLineCleanup.source;
      if (updated == source) {
        continue;
      }
      final updatedParse = parseString(
        content: updated,
        path: file.path,
        throwIfDiagnostics: false,
      );
      if (_introducesDiagnostics(originalParse, updatedParse)) {
        throw StateError('comment cleanup introduced parser diagnostics');
      }

      file.writeAsStringSync(updated);
      modifiedFiles++;
      removedComments += comments.length;
      removedBlankLines += blankLineCleanup.removedLines;
    } catch (error) {
      failedFiles.add(
        DartCommentCleanupFailure(
          path: p.relative(file.path, from: projectPath),
          reason: '$error',
        ),
      );
    }
  }

  final result = DartCommentCleanupResult(
    scannedFiles: files.length,
    modifiedFiles: modifiedFiles,
    removedComments: removedComments,
    removedBlankLines: removedBlankLines,
    formattedFiles: 0,
    formatFailedFiles: const [],
    failedFiles: List.unmodifiable(failedFiles),
  );
  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'dart_comment_cleanup',
    featureTitle: 'Dart 源码注释清理',
    mapping: {
      'generated_at': DateTime.now().toIso8601String(),
      'summary': {
        'scanned_files': result.scannedFiles,
        'modified_files': result.modifiedFiles,
        'removed_comments': result.removedComments,
        'removed_blank_lines': result.removedBlankLines,
        'formatted_files': result.formattedFiles,
        'format_failed_files': result.formatFailedFiles.length,
        'failed_files': result.failedFiles.length,
      },
      'scanned_files': result.scannedFiles,
      'modified_files': result.modifiedFiles,
      'removed_comments': result.removedComments,
      'removed_blank_lines': result.removedBlankLines,
      'formatted_files': result.formattedFiles,
      'format_failed_files':
          result.formatFailedFiles.map((failure) => failure.toJson()).toList(),
      'failed_files':
          result.failedFiles.map((failure) => failure.toJson()).toList(),
    },
  );

  Log.log('Dart comment cleanup complete.');
  Log.log('Scanned files: ${result.scannedFiles}');
  Log.log('Modified files: ${result.modifiedFiles}');
  Log.log('Removed comments: ${result.removedComments}');
  Log.log('Removed blank lines: ${result.removedBlankLines}');
  Log.log('Formatted files: ${result.formattedFiles}');
  if (result.failedFiles.isNotEmpty) {
    Log.log('Failed files: ${result.failedFiles.length}');
    for (final failure in result.failedFiles) {
      Log.log('  ${failure.path}: ${failure.reason}');
    }
  }
  Log.log('Mapping document: $mappingPath');

  return result;
}

List<_CommentRange> _collectCommentRanges(ParseStringResult parseResult) {
  final comments = <_CommentRange>[];
  final seenOffsets = <int>{};
  Token? token = parseResult.unit.beginToken;

  while (token != null) {
    Token? comment = token.precedingComments;
    while (comment != null) {
      if (seenOffsets.add(comment.offset)) {
        comments.add(
          _CommentRange(
            offset: comment.offset,
            length: comment.length,
            lexeme: comment.lexeme,
          ),
        );
      }
      comment = comment.next;
    }
    if (token.type == TokenType.EOF) {
      break;
    }
    token = token.next;
  }

  comments.sort((left, right) => right.offset.compareTo(left.offset));
  return comments;
}

String _removeCommentRanges(String source, List<_CommentRange> comments) {
  var updated = source;
  for (final comment in comments) {
    updated = updated.replaceRange(
      comment.offset,
      comment.offset + comment.length,
      _commentReplacement(comment.lexeme),
    );
  }
  return updated;
}

_BlankLineCleanupResult _removeCodeBlankLines(String source) {
  final parseResult = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final tokenRanges = _collectTokenRanges(parseResult);
  final buffer = StringBuffer();
  var removedLines = 0;
  var offset = 0;

  while (offset < source.length) {
    final lineStart = offset;
    var lineEnd = offset;
    while (lineEnd < source.length &&
        source.codeUnitAt(lineEnd) != 10 &&
        source.codeUnitAt(lineEnd) != 13) {
      lineEnd++;
    }

    var nextOffset = lineEnd;
    if (nextOffset < source.length) {
      if (source.codeUnitAt(nextOffset) == 13 &&
          nextOffset + 1 < source.length &&
          source.codeUnitAt(nextOffset + 1) == 10) {
        nextOffset += 2;
      } else {
        nextOffset++;
      }
    }

    final line = source.substring(lineStart, lineEnd);
    final isBlankLine = line.trim().isEmpty;
    final isInsideToken = _rangeIntersectsToken(
      lineStart,
      nextOffset,
      tokenRanges,
    );
    if (isBlankLine && !isInsideToken) {
      removedLines++;
    } else {
      buffer.write(source.substring(lineStart, nextOffset));
    }

    offset = nextOffset;
  }

  return _BlankLineCleanupResult(
    source: buffer.toString(),
    removedLines: removedLines,
  );
}

List<(int, int)> _collectTokenRanges(ParseStringResult parseResult) {
  final ranges = <(int, int)>[];
  Token? token = parseResult.unit.beginToken;
  while (token != null) {
    if (token.length > 0) {
      ranges.add((token.offset, token.offset + token.length));
    }
    if (token.type == TokenType.EOF) {
      break;
    }
    token = token.next;
  }
  return ranges;
}

bool _rangeIntersectsToken(int start, int end, List<(int, int)> tokenRanges) {
  for (final (tokenStart, tokenEnd) in tokenRanges) {
    if (tokenEnd <= start) {
      continue;
    }
    if (tokenStart >= end) {
      return false;
    }
    return true;
  }
  return false;
}

String _commentReplacement(String lexeme) {
  if (lexeme.startsWith('//')) {
    return '';
  }
  final lineBreaks = RegExp(r'\r\n|\r|\n')
      .allMatches(lexeme)
      .map((match) => match.group(0)!)
      .join();
  return lineBreaks.isEmpty ? ' ' : lineBreaks;
}

bool _introducesDiagnostics(
  ParseStringResult original,
  ParseStringResult updated,
) {
  final remaining = <String, int>{};
  for (final error in original.errors) {
    final signature = '${error.errorCode.name}:${error.message}';
    remaining[signature] = (remaining[signature] ?? 0) + 1;
  }
  for (final error in updated.errors) {
    final signature = '${error.errorCode.name}:${error.message}';
    final count = remaining[signature] ?? 0;
    if (count == 0) {
      return true;
    }
    remaining[signature] = count - 1;
  }
  return false;
}
