import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myune_music/lyrics/fetcher/kugou_fetcher.dart';
import 'package:myune_music/lyrics/fetcher/lyric_song_match.dart';
import 'package:myune_music/lyrics/fetcher/netease_fetcher.dart';
import 'package:myune_music/lyrics/fetcher/qqmusic_fetcher.dart';

const _title = 'Audit C';
const _artist = 'StarNote Audit';

http.Response _json(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _qqResponse(Map<String, dynamic> data) => {
  'code': 0,
  'request': {'code': 0, 'data': data},
};

void main() {
  test('matching tolerates formatting but keeps title editions distinct', () {
    expect(matchesLyricSong(
      title: 'Ａudit C！', artist: 'StarNote Audit；Duet',
      candidateTitles: ['audit c'], candidateArtists: ['DUET'],
    ), isTrue);
    expect(matchesLyricSong(
      title: _title, artist: _artist,
      candidateTitles: ['Audit C (Remix)'], candidateArtists: [_artist],
    ), isFalse);
    expect(matchesLyricSong(
      title: _title, artist: '',
      candidateTitles: ['Audit C'], candidateArtists: ['another artist'],
    ), isTrue);
  });

  for (final includeMatch in [false, true]) {
    test('QQ selects only a matching track (match present: $includeMatch)', () async {
      final downloaded = <int>[];
      final result = await http.runWithClient(
        () => QQMusicFetcher().search(_title, _artist),
        () => MockClient((request) async {
          final call = jsonDecode(request.body)['request'] as Map;
          switch (call['method']) {
            case 'GetSession':
              return _json(_qqResponse({'session': {}}));
            case 'DoSearchForQQMusicDesktop':
              return _json(_qqResponse({
                'body': {'song': {'list': [
                  {'id': 11, 'title': 'Unrelated', 'singer': [{'name': _artist}]},
                  {'id': 12, 'title': _title, 'singer': [{'name': 'another artist'}]},
                  if (includeMatch)
                    {'id': 13, 'title': 'Audit C！', 'singer': [{'name': _artist}]},
                ]}},
              }));
            case 'GetPlayLyricInfo':
              downloaded.add(call['param']['songID'] as int);
              return _json(_qqResponse({}));
            default:
              fail('Unexpected QQ request ${call['method']}');
          }
        }),
      );
      expect(downloaded, includeMatch ? [13] : isEmpty);
      expect(result.songId, includeMatch ? 13 : isNull);
    });

    test('NetEase selects only a matching track (match present: $includeMatch)', () async {
      var lyricRequests = 0;
      final result = await http.runWithClient(
        () => NeteaseFetcher().search(_title, _artist),
        () => MockClient((request) async {
          if (request.url.path.endsWith('/cloudsearch/pc')) {
            return _json({
              'code': 200,
              'result': {'songs': [
                {'id': 21, 'name': 'Unrelated', 'ar': [{'name': _artist}]},
                {'id': 22, 'name': _title, 'ar': [{'name': 'another artist'}]},
                if (includeMatch)
                  {'id': 23, 'name': 'Audit C！', 'ar': [{'name': _artist}]},
              ]},
            });
          }
          expect(request.url.path, '/eapi/song/lyric/v1');
          lyricRequests++;
          return _json({'code': 200});
        }),
      );
      expect(lyricRequests, includeMatch ? 1 : 0);
      expect(result.songId, includeMatch ? 23 : isNull);
    });

    test('Kugou selects only a matching track (match present: $includeMatch)', () async {
      final requestedHashes = <String>[];
      await http.runWithClient(
        () => KugouFetcher().search(_title, _artist),
        () => MockClient((request) async {
          if (request.url.path == '/api/v3/search/song') {
            return _json({
              'status': 1,
              'data': {'info': [
                {'hash': 'wrong-title', 'songname': 'Unrelated', 'singername': _artist},
                {'hash': 'wrong-artist', 'songname': _title, 'singername': 'another artist'},
                if (includeMatch)
                  {'hash': 'right', 'songname': 'Audit C！', 'singername': _artist},
              ]},
            });
          }
          expect(request.url.host, 'krcs.kugou.com');
          requestedHashes.add(request.url.queryParameters['hash']!);
          return _json({'status': 200, 'candidates': []});
        }),
      );
      expect(requestedHashes, includeMatch ? ['right'] : isEmpty);
    });
  }
}
