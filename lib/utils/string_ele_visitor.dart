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
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (_isWrappedInDes(node)) return;
    if (_isInDirective(node)) return;
    if (_isInAnnotation(node)) return;
    if (node.inConstantContext) return;
    if (_isInRequiredConstantExpression(node)) return;
    if (_isInSwitchCaseExpression(node)) return;
    if (_isInDartPattern(node)) return;

    final value = node.value;
    if (value.isEmpty) return;

    final encrypted = StringCryptUtils.encrypt(value, sek);
    final replacement = '$funcName("$sep$encrypted")';
    replacements.add(StringReplacementData(node.offset, node.end, replacement));

    super.visitSimpleStringLiteral(node);
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
