/// Separators are literal strings, including multi-character words and regex
/// metacharacters. Prefer the longest delimiter when configured values overlap.
List<String> splitArtistNames(String artists, Iterable<String> separators) {
  final valid = separators.where((item) => item.trim().isNotEmpty).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final parts = valid.isEmpty
      ? [artists]
      : artists.split(RegExp(valid.map(RegExp.escape).join('|')));
  return parts.map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
}
