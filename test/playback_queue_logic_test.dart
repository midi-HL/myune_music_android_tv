import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playback_queue_logic.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/utils/latest_operation.dart';

void main() {
  group('queue edits preserve the playing item', () {
    for (final queue in <List<String>>[['A'], ['A', 'B', 'C']]) {
      test('setting current last song next is a no-op: $queue', () {
        final result = moveQueueItemNext(queue, queue.length - 1, queue.last, (s) => s);
        expect(result.changed, isFalse);
        expect(result.items, queue);
        expect(result.currentIndex, queue.length - 1);
      });
    }
    test('moving an earlier item preserves current identity', () {
      final edit = moveQueueItemNext(['A', 'B', 'C'], 1, 'A', (s) => s);
      expect(edit.items, ['B', 'A', 'C']);
      expect(edit.items[edit.currentIndex], 'B');
      expect(edit.items[edit.nextIndex], 'A');
    });
    test('adding a new item keeps existing current index', () {
      final edit = moveQueueItemNext(['A', 'B'], 0, 'C', (s) => s);
      expect(edit.items, ['A', 'C', 'B']);
      expect(edit.currentIndex, 0);
    });
    test('reorder/deletion locates the same playing path', () {
      expect(reconcilePlayingIndex(['B', 'A', 'C'], 'B', 1), 0);
      expect(reconcilePlayingIndex(['A', 'C'], 'B', 1), 0);
      expect(reconcilePlayingIndex([], 'B', 0), -1);
    });
  });

  test('opaque and network paths survive missing-file cleanup', () {
    for (final path in ['content://media/1', 'http://127.0.0.1:18765/starnote/TOKEN',
      'https://host/music.mp3', 'bilibili:BV1:1', 'nas:source:file', 'gd:file']) {
      expect(canCheckAsLocalFile(path), isFalse, reason: path);
      final song = Song(title: 'A', artist: 'B', filePath: path);
      expect(song.normalizedPath, path, reason: path);
    }
    expect(canCheckAsLocalFile('/Music/A.mp3'), isTrue);
    expect(canCheckAsLocalFile(r'C:\Music\A.mp3'), isTrue);
  });

  test('a failed directory scan never commits a partial refresh', () async {
    var stored = <String>{'old-one', 'old-two'};
    await expectLater(() async {
      final scan = await collectFolderPaths(['first', 'second'], (folder) async {
        if (folder == 'second') throw StateError('permission revoked');
        return ['new-one'];
      });
      stored = scan;
    }(), throwsStateError);
    expect(stored, {'old-one', 'old-two'});
  });

  test('old playback state remains readable', () {
    final state = PlaybackState.fromJson({'playlistId': 'P', 'songIndex': 2});
    expect(state.usesQueue, isFalse);
    expect(state.songIndex, 2);
    expect(state.songPath, isNull);
  });
  test('independent queue identity, cursor and shuffle order round trip', () {
    final state = PlaybackState(playlistId: 'P', songIndex: 1, usesQueue: true,
      songPath: 'B', shuffleOrder: [1, 2, 0]);
    final loaded = PlaybackState.fromJson(state.toJson());
    expect(loaded.usesQueue, isTrue);
    expect(loaded.songIndex, 1);
    expect(loaded.songPath, 'B');
    expect(loaded.shuffleOrder, [1, 2, 0]);
  });

  test('latest preparation wins even when the old preparation finishes last', () async {
    final gate = LatestOperation();
    final old = gate.begin();
    final current = gate.begin();
    final effects = <String>[];
    await gate.run(current, (_) async { effects.add('current'); });
    await gate.run(old, (_) async { effects.add('old'); });
    expect(effects, ['current']);
  });
  test('native commits are serialized and stale work stops after awaiting', () async {
    final gate = LatestOperation();
    final started = Completer<void>();
    final release = Completer<void>();
    final effects = <String>[];
    final old = gate.begin();
    final first = gate.run(old, (active) async {
      effects.add('old-start'); started.complete(); await release.future;
      if (active()) effects.add('old-open');
    });
    await started.future;
    final current = gate.begin();
    final second = gate.run(current, (_) async { effects.add('current-open'); });
    release.complete();
    await Future.wait([first, second]);
    expect(effects, ['old-start', 'current-open']);
  });
  test('a failed commit does not poison the next playback command', () async {
    final gate = LatestOperation();
    await expectLater(gate.run(gate.begin(), (_) async { throw StateError('fail'); }), throwsStateError);
    var called = false;
    await gate.run(gate.begin(), (_) async { called = true; });
    expect(called, isTrue);
  });
  test('manual NEXT after native gapless transition advances past the already-playing item', () async {
    final gate = LatestOperation();
    var currentIndex = 0;
    final paths = ['A', 'B', 'C'];
    final metadata = Completer<void>();
    final metadataStarted = Completer<void>();
    final transition = gate.begin();
    // The native playlist event means B is already audible, before metadata resolves.
    currentIndex = nextGaplessIndex(currentIndex, paths.length);
    final loading = gate.run(transition, (active) async {
      metadataStarted.complete();
      await metadata.future;
      if (active()) currentIndex = 1;
    });
    await metadataStarted.future;
    currentIndex = nextGaplessIndex(currentIndex, paths.length);
    final manual = gate.begin();
    String? opened;
    final playing = gate.run(manual, (_) async { opened = paths[currentIndex]; });
    metadata.complete();
    await Future.wait([loading, playing]);
    expect(opened, 'C');
    expect(currentIndex, 2);
  });
  for (final resume in [false, true]) {
    test('pause while preparing preserves intent (resume=$resume)', () async {
      final gate = LatestOperation();
      final intent = PlaybackIntent()..play();
      final prepare = Completer<void>();
      final request = gate.begin();
      bool? openedPlaying;
      final choosing = () async {
        await prepare.future;
        await gate.run(request, (_) async { openedPlaying = intent.playRequested; });
      }();
      intent.pause();
      if (resume) intent.play();
      prepare.complete();
      await choosing;
      expect(openedPlaying, resume);
    });
  }
}
