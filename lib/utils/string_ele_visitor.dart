import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:obfuscateflutter/utils/string_crypt_utils.dart';

class StringReplacementData {
  final int offset;
  final int end;
  final String replacement;
  const StringReplacementData(this.offset, this.end, this.replacement);
}

class StringEncryptVisitor extends RecursiveAstVisitor<void> {
  final String sep;
  final int sek;
  final String funcName;

  final List<StringReplacementData> replacements = [];

  StringEncryptVisitor(this.sep, this.sek, this.funcName);

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (_shouldSkipStringLiteral(node)) return;

    final replacement = _buildStringExpression(node);
    if (replacement == null) return;

    replacements.add(StringReplacementData(node.offset, node.end, replacement));
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.parent is AdjacentStrings) return;
    if (_shouldSkipStringLiteral(node)) return;

    final value = node.value;
    if (value.isEmpty) return;

    final encrypted = StringCryptUtils.encrypt(value, sek);
    final replacement = '$funcName("$sep$encrypted")';
    replacements.add(StringReplacementData(node.offset, node.end, replacement));

    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.parent is AdjacentStrings) return;
    if (_shouldSkipStringLiteral(node)) return;

    final replacement = _buildStringExpression(node);
    if (replacement == null) return;

    replacements.add(StringReplacementData(node.offset, node.end, replacement));
  }

  bool _shouldSkipStringLiteral(StringLiteral node) {
    if (_isWrappedInDes(node)) return true;
    if (_isInDirective(node)) return true;
    if (_isInAnnotation(node)) return true;
    if (node.inConstantContext) return true;
    if (_isInPreservedNamedArgument(node)) return true;
    if (_isInRequiredConstantExpression(node)) return true;
    if (_isInSwitchCaseExpression(node)) return true;
    if (_isInDartPattern(node)) return true;
    return false;
  }

  String? _buildStringExpression(StringLiteral node) {
    final parts = <String>[];
    _collectStringExpressionParts(node, parts);
    if (parts.isEmpty) return null;
    return parts.join(' + ');
  }

  void _collectStringExpressionParts(StringLiteral node, List<String> parts) {
    if (node is AdjacentStrings) {
      for (final string in node.strings) {
        _collectStringExpressionParts(string, parts);
      }
      return;
    }

    if (node is SimpleStringLiteral) {
      _addEncryptedPart(node.value, parts);
      return;
    }

    if (node is StringInterpolation) {
      for (final element in node.elements) {
        if (element is InterpolationString) {
          _addEncryptedPart(element.value, parts);
        } else if (element is InterpolationExpression) {
          parts.add(_interpolationExpressionSource(element));
        }
      }
    }
  }

  void _addEncryptedPart(String value, List<String> parts) {
    if (value.isEmpty) return;

    final encrypted = StringCryptUtils.encrypt(value, sek);
    parts.add('$funcName("$sep$encrypted")');
  }

  String _interpolationExpressionSource(InterpolationExpression element) {
    final expression = element.expression;
    final source = expression.toSource();
    if (expression is SimpleIdentifier) {
      return '$source.toString()';
    }
    return '($source).toString()';
  }

  bool _isWrappedInDes(AstNode node) {
    final parent = node.parent;
    if (parent is ArgumentList) {
      final grandparent = parent.parent;
      if (grandparent is MethodInvocation) {
        return grandparent.methodName.name == funcName;
      }
    }
    return false;
  }

  bool _isInPreservedNamedArgument(AstNode node) {
    AstNode child = node;
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is NamedExpression && identical(parent.expression, child)) {
        return _preservedNamedArguments.contains(parent.name.label.name);
      }
      child = parent;
      parent = parent.parent;
    }
    return false;
  }

  bool _isInDirective(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is ImportDirective ||
          current is ExportDirective ||
          current is PartDirective ||
          current is PartOfDirective) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isInAnnotation(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is Annotation) {
        return true;
      }
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
      if (current is DartPattern) {
        return true;
      }
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
      if (_isInConstConstructorInitializer(child, parent)) {
        return true;
      }
      if (_isInstanceFieldInitializerInClassWithConstConstructor(
        child,
        parent,
      )) {
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

const _preservedNamedArguments = {
  'key',
  'event',
  'message',
};
