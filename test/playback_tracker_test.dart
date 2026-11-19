import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/statistics_page/playback_tracker.dart';

void main() {
  final song = Song(title: 'song', artist: 'artist', filePath: '/song.mp3');
  test('30 seconds of normal playback records exactly one play', () {
    fakeAsync((time) {
      var records = 0;
      final tracker = PlaybackTracker.forTesting(
        now: () => DateTime(2026).add(time.elapsed), record: (_) { records++; });
      tracker.startTracking(song);
      time.elapse(const Duration(seconds: 29));
      expect(records, 0);
      time.elapse(const Duration(seconds: 1));
      expect(records, 1);
      time.elapse(const Duration(seconds: 60));
      expect(records, 1);
      tracker.stopTracking();
    });
  });
  test('repeated resume callbacks do not lose elapsed time across pause', () {
    fakeAsync((time) {
      var records = 0;
      final tracker = PlaybackTracker.forTesting(
        now: () => DateTime(2026).add(time.elapsed), record: (_) { records++; });
      tracker.startTracking(song);
      time.elapse(const Duration(seconds: 10));
      tracker.resumeTracking();
      time.elapse(const Duration(seconds: 5));
      tracker.pauseTracking();
      time.elapse(const Duration(seconds: 60));
      expect(records, 0);
      tracker.resumeTracking();
      time.elapse(const Duration(seconds: 14));
      expect(records, 0);
      time.elapse(const Duration(seconds: 1));
      expect(records, 1);
      tracker.stopTracking();
    });
  });
  test('stop cancels the pending statistics timer', () {
    fakeAsync((time) {
      var records = 0;
      final tracker = PlaybackTracker.forTesting(
        now: () => DateTime(2026).add(time.elapsed), record: (_) { records++; });
      tracker.startTracking(song);
      time.elapse(const Duration(seconds: 10));
      tracker.stopTracking();
      time.elapse(const Duration(seconds: 60));
      expect(records, 0);
    });
  });
}
