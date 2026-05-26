import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:obfuscateflutter/utils/string_ele_visitor.dart';
import 'package:test/test.dart';

void main() {
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
}
