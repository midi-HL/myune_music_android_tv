import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/tv/tv_actions.dart';
import 'package:myune_music/tv/tv_key_map.dart';

void main() {
  test('media transport commands retain their distinct meanings', () {
    for (final source in TvInputSource.values) {
      TvAction? resolve(int key) => TvKeyMaps.resolve(keyCode: key, source: source, custom: {});
      expect(resolve(AndroidKeyCode.mediaPlay), TvAction.play);
      expect(resolve(AndroidKeyCode.mediaPause), TvAction.pause);
      expect(resolve(AndroidKeyCode.mediaStop), TvAction.stop);
      expect(resolve(AndroidKeyCode.mediaPlayPause), TvAction.playPause);
    }
  });
  test('existing persisted names and custom bindings remain valid', () {
    expect(tvActionFromName('playPause'), TvAction.playPause);
    expect(tvActionFromName('openQueue'), TvAction.openQueue);
    expect(TvKeyMaps.resolve(keyCode: AndroidKeyCode.mediaPlay, source: TvInputSource.remote,
      custom: {AndroidKeyCode.mediaPlay: TvAction.nextTrack}), TvAction.nextTrack);
  });
}
