import '../../utils/artist_separator_logic.dart';

final _spacingAndPunctuation = RegExp(r'[\s\p{Z}\p{P}]+', unicode: true);
const _artistSeparators = [';', '、', '；', '，', ',', ' / '];

String _normalize(String value) => String.fromCharCodes(
  value.runes.map((rune) => rune >= 0xFF01 && rune <= 0xFF5E
      ? rune - 0xFEE0
      : rune),
).toLowerCase().replaceAll(_spacingAndPunctuation, '');

Set<String> _artistNames(Iterable<String> values) => values
    .expand((value) => splitArtistNames(value, _artistSeparators))
    .map(_normalize)
    .where((name) => name.isNotEmpty)
    .toSet();

/// Require agreement on song identity before downloading a candidate's lyrics.
/// Preserve words in titles, including version names such as live or remix.
bool matchesLyricSong({
  required String title,
  required String artist,
  required Iterable<String> candidateTitles,
  required Iterable<String> candidateArtists,
}) {
  final normalizedTitle = _normalize(title);
  if (normalizedTitle.isEmpty ||
      !candidateTitles.any((candidate) => _normalize(candidate) == normalizedTitle)) {
    return false;
  }
  // LyricsHandler passes an empty artist when the file's artist is unknown.
  final requestedArtists = _artistNames([artist]);
  if (requestedArtists.isEmpty) return true;
  return _artistNames(candidateArtists).any(requestedArtists.contains);
}
