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
    if (_isInConstContext(node)) return;

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

  bool _isInConstContext(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is VariableDeclaration && current.isConst) {
        return true;
      }
      if (current is InstanceCreationExpression &&
          current.keyword?.lexeme == 'const') {
        return true;
      }
      if (current is TypedLiteral && current.constKeyword != null) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }
}
