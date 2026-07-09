import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:obfuscateflutter/utils/string_crypt_utils.dart';
import 'package:obfuscateflutter/utils/string_ele_visitor.dart';
import 'package:test/test.dart';

void main() {
  test('does not encrypt part-of directive uri strings', () {
    const source = '''
part of 'models/user_model.dart';

String runtime() => 'runtime';
''';

    final unit = parseString(content: source).unit;
    final visitor = StringEncryptVisitor('SEP', 7, 'des');

    unit.accept(visitor);

    final replacedSources = visitor.replacements
        .map((replacement) =>
            source.substring(replacement.offset, replacement.end))
        .toList();

    expect(replacedSources, isNot(contains("'models/user_model.dart'")));
    expect(replacedSources, contains("'runtime'"));
  });

  test('does not encrypt string switch case labels', () {
    const source = '''
String label(String status) {
  switch (status) {
    case 'ready':
      return 'done';
    default:
      return 'unknown';
  }
}
''';

    final unit = parseString(content: source).unit;
    final visitor = StringEncryptVisitor('SEP', 7, 'des');

    unit.accept(visitor);

    final replacedSources = visitor.replacements
        .map((replacement) =>
            source.substring(replacement.offset, replacement.end))
        .toList();

    expect(replacedSources, isNot(contains("'ready'")));
    expect(replacedSources, contains("'done'"));
    expect(replacedSources, contains("'unknown'"));
  });

  test('does not encrypt strings that must stay constant expressions', () {
    const source = '''
enum Status {
  ready('ready');

  const Status(this.label);
  final String label;
}

class Config {
  const Config({this.name = 'default'});
  final String name;
}

class Holder {
  const Holder() : value = 'held';
  final String value;
}

class FieldHolder {
  const FieldHolder();
  final String value = 'field';
}

const values = ('record', ['list']);

String runtime() => 'runtime';
''';

    final unit = parseString(content: source).unit;
    final visitor = StringEncryptVisitor('SEP', 7, 'des');

    unit.accept(visitor);

    final replacedSources = visitor.replacements
        .map((replacement) =>
            source.substring(replacement.offset, replacement.end))
        .toList();

    expect(replacedSources, isNot(contains("'ready'")));
    expect(replacedSources, isNot(contains("'default'")));
    expect(replacedSources, isNot(contains("'held'")));
    expect(replacedSources, isNot(contains("'field'")));
    expect(replacedSources, isNot(contains("'record'")));
    expect(replacedSources, isNot(contains("'list'")));
    expect(replacedSources, contains("'runtime'"));
  });

  test('rewrites adjacent interpolated strings as valid concatenation', () {
    const source = r'''
String des(String s) => s;

String report(String effectType, String url) {
  return "type: vap"
      "$effectType url:$url download error.";
}
''';

    final unit = parseString(content: source).unit;
    final visitor = StringEncryptVisitor('SEP', 7, 'des');

    unit.accept(visitor);

    var modified = source;
    for (final replacement
        in visitor.replacements..sort((a, b) => b.offset.compareTo(a.offset))) {
      modified = modified.replaceRange(
        replacement.offset,
        replacement.end,
        replacement.replacement,
      );
    }

    expect(parseString(content: modified).errors, isEmpty);
    expect(
      modified,
      contains(
        'des("SEP${StringCryptUtils.encrypt('type: vap', 7)}") + '
        'effectType.toString() + '
        'des("SEP${StringCryptUtils.encrypt(' url:', 7)}") + '
        'url.toString() + '
        'des("SEP${StringCryptUtils.encrypt(' download error.', 7)}")',
      ),
    );
  });

  test('keeps report message fields while encrypting interpolated detail text',
      () {
    const source = r'''
class MsgReportKey {
  static const playEffect = 1;
}

class MsgReport {
  static void uploadErr({Object? key, String? message, String? detail}) {}
}

void send(String effectType, String url) {
  MsgReport.uploadErr(
    key: MsgReportKey.playEffect,
    message: "getEffectFilePath",
    detail: "type: vap"
        "$effectType url:$url download error.",
  );
}
''';

    final unit = parseString(content: source).unit;
    final visitor = StringEncryptVisitor('SEP', 7, 'des');

    unit.accept(visitor);

    var modified = source;
    for (final replacement
        in visitor.replacements..sort((a, b) => b.offset.compareTo(a.offset))) {
      modified = modified.replaceRange(
        replacement.offset,
        replacement.end,
        replacement.replacement,
      );
    }

    expect(parseString(content: modified).errors, isEmpty);
    expect(modified, contains('message: "getEffectFilePath"'));
    expect(modified, isNot(contains('detail: "type: vap"')));
    expect(modified, contains('effectType.toString()'));
    expect(modified, contains('url.toString()'));
  });
}
