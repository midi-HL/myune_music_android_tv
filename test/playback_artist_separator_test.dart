import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/utils/artist_separator_logic.dart';

void main() {
  test('multi-character separators do not split ordinary artist-name letters', () {
    expect(splitArtistNames('Sea feat.Tom', ['feat.']), ['Sea', 'Tom']);
    expect(splitArtistNames('SeaTeam', ['feat.']), ['SeaTeam']);
  });
  test('default single-character delimiters keep their existing behavior', () {
    expect(splitArtistNames('甲;乙、丙；丁，戊,己', [';', '、', '；', '，', ',']),
      ['甲', '乙', '丙', '丁', '戊', '己']);
  });
  test('regex metacharacters and delimiter overlaps are literal', () {
    expect(splitArtistNames('A+B.*C', ['+', '.*']), ['A', 'B', 'C']);
    expect(splitArtistNames('A::B', [':', '::']), ['A', 'B']);
    expect(splitArtistNames('A|B', [';']), ['A|B']);
  });
  test('empty delimiter settings do not split every character', () {
    expect(splitArtistNames(' Artist ', ['', ' ']), ['Artist']);
    expect(splitArtistNames('', [';']), isEmpty);
  });
}
