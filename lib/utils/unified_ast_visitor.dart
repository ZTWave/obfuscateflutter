import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:obfuscateflutter/utils/string_crypt_utils.dart';

class StringReplacementData {
  final int offset;
  final int end;
  final String replacement;
  const StringReplacementData(this.offset, this.end, this.replacement);
}

/// AST visitor that handles both string encryption and file-rename URI rewriting.
///
/// In a single AST walk it:
/// - Encrypts SimpleStringLiteral nodes (same rules as [StringEncryptVisitor])
/// - Rewrites URIs in ImportDirective / ExportDirective / PartDirective / PartOfDirective
///   when the referenced file is in [fileMappings].
///
/// Both sets of changes produce [StringReplacementData] offsets applied together,
/// so the caller does one source rewrite pass.
class UnifiedObfuscationVisitor extends RecursiveAstVisitor<void> {
  final Map<String, String> _fileMappings;
  final String _sep;
  final int _sek;
  final String _funcName;

  final List<StringReplacementData> replacements = [];
  var importRewriteCount = 0;
  var stringEncryptCount = 0;

  UnifiedObfuscationVisitor(
    this._fileMappings,
    this._sep,
    this._sek,
    this._funcName,
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

    final segments = uriStr.split('/');
    final lastSegment = segments.last;

    if (!lastSegment.endsWith('.dart')) return;
    final basename =
        lastSegment.substring(0, lastSegment.length - '.dart'.length);
    if (!_fileMappings.containsKey(basename)) return;

    final newBasename = _fileMappings[basename]!;
    segments[segments.length - 1] = '$newBasename.dart';
    final newUri = segments.join('/');

    final quote = uriLiteral.isSingleQuoted ? "'" : '"';
    final replacement = '$quote$newUri$quote';

    if (replacement == uriLiteral.literal.lexeme) return;

    replacements.add(
      StringReplacementData(uriLiteral.offset, uriLiteral.end, replacement),
    );
    importRewriteCount++;
  }

  SimpleStringLiteral? _findUriStringLiteral(AstNode directive) {
    for (final child in directive.childEntities) {
      if (child is SimpleStringLiteral) {
        return child;
      }
    }
    return null;
  }

  // ── String encryption ────────────────────────────────────────────────

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    // These skip-checks must run before encryption, including the ones
    // that walk the parent chain.  The directive skip already covers
    // URI literals visited above, so there is no conflict.
    if (_isWrappedInDes(node)) return;
    if (_isInDirective(node)) return;
    if (_isInAnnotation(node)) return;
    if (node.inConstantContext) return;
    if (_isInRequiredConstantExpression(node)) return;
    if (_isInSwitchCaseExpression(node)) return;
    if (_isInDartPattern(node)) return;

    final value = node.value;
    if (value.isEmpty) return;

    final encrypted = StringCryptUtils.encrypt(value, _sek);
    final replacement = '$_funcName("$_sep$encrypted")';
    replacements
        .add(StringReplacementData(node.offset, node.end, replacement));
    stringEncryptCount++;

    super.visitSimpleStringLiteral(node);
  }

  // ── String encryption skip checks (same as StringEncryptVisitor) ─────

  bool _isWrappedInDes(AstNode node) {
    final parent = node.parent;
    if (parent is ArgumentList) {
      final grandparent = parent.parent;
      if (grandparent is MethodInvocation) {
        return grandparent.methodName.name == _funcName;
      }
    }
    return false;
  }

  bool _isInDirective(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is ImportDirective ||
          current is ExportDirective ||
          current is PartDirective) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isInAnnotation(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is Annotation) return true;
      current = current.parent;
    }
    return false;
  }

  bool _isInSwitchCaseExpression(AstNode node) {
    AstNode? child = node;
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is SwitchCase && identical(parent.expression, child)) {
        return true;
      }
      child = parent;
      parent = parent.parent;
    }
    return false;
  }

  bool _isInDartPattern(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is DartPattern) return true;
      current = current.parent;
    }
    return false;
  }

  bool _isInRequiredConstantExpression(AstNode node) {
    AstNode child = node;
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is DefaultFormalParameter &&
          identical(parent.defaultValue, child)) {
        return true;
      }
      if (_isInConstConstructorInitializer(child, parent)) return true;
      if (_isInstanceFieldInitializerInClassWithConstConstructor(
          child, parent)) {
        return true;
      }
      child = parent;
      parent = parent.parent;
    }
    return false;
  }

  bool _isInConstConstructorInitializer(AstNode child, AstNode parent) {
    if (parent is! ConstructorInitializer) return false;
    AstNode? current = parent.parent;
    while (current != null) {
      if (current is ConstructorDeclaration) {
        return current.constKeyword != null;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isInstanceFieldInitializerInClassWithConstConstructor(
    AstNode child,
    AstNode parent,
  ) {
    if (parent is! VariableDeclaration ||
        !identical(parent.initializer, child)) {
      return false;
    }
    final declarationList = parent.parent;
    if (declarationList is! VariableDeclarationList) return false;
    final fieldDeclaration = declarationList.parent;
    if (fieldDeclaration is! FieldDeclaration || fieldDeclaration.isStatic) {
      return false;
    }
    final classDeclaration = fieldDeclaration.parent;
    if (classDeclaration is! ClassDeclaration) return false;
    return classDeclaration.members.whereType<ConstructorDeclaration>().any(
          (member) => member.constKeyword != null,
        );
  }
}
