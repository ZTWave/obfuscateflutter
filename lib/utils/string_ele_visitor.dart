import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:obfuscateflutter/log.dart';

class StringEleVisitor extends RecursiveAstVisitor<void> {
  @override
  void visitImportDirective(ImportDirective node) {
    Log.log('field -> $node');
    super.visitImportDirective(node);
  }

  @override
  visitFieldDeclaration(FieldDeclaration node) {
    Log.log('field -> $node');

    /*final tokens = node.childEntities.whereType<Token>();

    if (tokens.isNotEmpty) {
      Log.log('find tokens -> $tokens');

      if (tokens.contains(Keyword.CONST)) {
        Log.log('find tokens -> $tokens is Const skip');
        return super.visitFieldDeclaration(node);
      }
    } */

    return super.visitFieldDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    Log.log('variable -> $node');
    Log.log('parent -> ${node.parent}');

    final isConst = node.isConst;

    Log.log('SKIP! node is const -> $isConst}');
    if (isConst) {
      return super.visitVariableDeclaration(node);
    }
    final nodeInitializer = node.initializer;
    final niChild = nodeInitializer?.childEntities;
    if (niChild?.whereType<InterpolationExpression>().isNotEmpty ?? false) {
      Log.log('SKIP! has center InterpolationExpression');
      return super.visitVariableDeclaration(node);
    }

    

    // node.parent?.accept();
    super.visitVariableDeclaration(node);
  }
}
