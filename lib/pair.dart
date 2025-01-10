class Pair<A, B> {
  A a;
  B b;

  Pair(this.a, this.b);

  @override
  String toString() {
    return "${a.toString()} -> ${b.toString()}";
  }
}

List<Pair<String, String>> toPairList(
  List<String> a,
  List<String> b,
) {
  List<Pair<String, String>> result = List.empty(growable: true);
  for (int i = 0; i < a.length; i++) {
    final fileNameOrigin = a[i];
    var fileNameOb = b.elementAtOrNull(i) ?? '';

    if (fileNameOrigin == 'main') {
      fileNameOb = 'main';
    }

    result.add(Pair(fileNameOrigin, fileNameOb));
  }
  return result;
}
