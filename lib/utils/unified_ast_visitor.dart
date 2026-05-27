import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

class StringReplacementData {
  final int offset;
  final int end;
  final String replacement;
  const StringReplacementData(this.offset, this.end, this.replacement);
}

/// AST visitor that handles file-rename URI rewriting.
///
/// It rewrites URIs in ImportDirective / ExportDirective / PartDirective /
/// PartOfDirective when the referenced file is in [fileMappings].
///
/// Changes produce [StringReplacementData] offsets applied together, so the
/// caller does one source rewrite pass.
class UnifiedObfuscationVisitor extends RecursiveAstVisitor<void> {
  final Map<String, String> _filePathMappings;
  final String _currentFilePath;
  final String _pubName;

  final List<StringReplacementData> replacements = [];
  var importRewriteCount = 0;
  var stringEncryptCount = 0;

  UnifiedObfuscationVisitor(
    this._filePathMappings,
    this._currentFilePath,
    this._pubName,
  );

  // ── Directive URI rewriting ──────────────────────────────────────────

  @override
  void visitImportDirective(ImportDirective node) {
    _tryRewriteNamespaceDirectiveUri(node);
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _tryRewriteNamespaceDirectiveUri(node);
    super.visitExportDirective(node);
  }

  @override
  void visitPartDirective(PartDirective node) {
    _tryRewriteDirectiveUri(node);
    super.visitPartDirective(node);
  }

  @override
  void visitPartOfDirective(PartOfDirective node) {
    _tryRewriteDirectiveUri(node);
    super.visitPartOfDirective(node);
  }

  void _tryRewriteNamespaceDirectiveUri(NamespaceDirective node) {
    final uriLiteral = _findUriStringLiteral(node);
    if (uriLiteral == null) return;
    _tryRewriteStringLiteralUri(uriLiteral);
  }

  void _tryRewriteDirectiveUri(AstNode node) {
    final uriLiteral = _findUriStringLiteral(node);
    if (uriLiteral == null) return;
    _tryRewriteStringLiteralUri(uriLiteral);
  }

  void _tryRewriteStringLiteralUri(SimpleStringLiteral uriLiteral) {
    final uriStr = uriLiteral.value;
    if (uriStr.isEmpty) return;

    final newUri = _rewriteUri(uriStr);
    if (newUri == null || newUri == uriStr) return;

    final quote = uriLiteral.isSingleQuoted ? "'" : '"';
    final replacement = '$quote$newUri$quote';

    if (replacement == uriLiteral.literal.lexeme) return;

    replacements.add(
      StringReplacementData(uriLiteral.offset, uriLiteral.end, replacement),
    );
    importRewriteCount++;
  }

  String? _rewriteUri(String uriStr) {
    if (!uriStr.endsWith('.dart')) return null;

    const packagePrefix = 'package:';
    final currentNewPath =
        _filePathMappings[_currentFilePath] ?? _currentFilePath;

    if (uriStr.startsWith(packagePrefix)) {
      final ownPackagePrefix = 'package:$_pubName/';
      if (!uriStr.startsWith(ownPackagePrefix)) return null;

      final targetPath = uriStr.substring(ownPackagePrefix.length);
      final newTargetPath = _filePathMappings[targetPath];
      if (newTargetPath == null) return null;
      return '$ownPackagePrefix$newTargetPath';
    }

    if (uriStr.contains(':')) return null;

    final currentDir = _dirnameOrDot(_currentFilePath);
    final targetPath = p.posix.normalize(p.posix.join(currentDir, uriStr));
    final newTargetPath = _filePathMappings[targetPath] ??
        _filePathMappings[_libRootFallback(uriStr)];
    if (newTargetPath == null) return null;

    final currentNewDir = _dirnameOrDot(currentNewPath);
    return p.posix.relative(newTargetPath, from: currentNewDir);
  }

  String _libRootFallback(String uriStr) {
    var path = uriStr;
    while (path.startsWith('../')) {
      path = path.substring(3);
    }
    if (path.startsWith('./')) {
      path = path.substring(2);
    }
    return p.posix.normalize(path);
  }

  String _dirnameOrDot(String path) {
    final dir = p.posix.dirname(path);
    return dir == '.' ? '' : dir;
  }

  SimpleStringLiteral? _findUriStringLiteral(AstNode directive) {
    for (final child in directive.childEntities) {
      if (child is SimpleStringLiteral) {
        return child;
      }
    }
    return null;
  }
}
