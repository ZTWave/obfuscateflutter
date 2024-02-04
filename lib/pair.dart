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
    result.add(Pair(a[i], b.elementAtOrNull(i) ?? ''));
  }
  return result;
}
