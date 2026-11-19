import 'dart:async';

/// User intent is independent from asynchronous preparation/native callbacks.
class PlaybackIntent {
  bool _playRequested = false;
  bool get playRequested => _playRequested;
  void play() => _playRequested = true;
  void pause() => _playRequested = false;
}

/// Serializes effectful commits while letting a newer user choice supersede
/// preparation or queued work from an older choice.
class LatestOperation {
  int _revision = 0;
  Future<void> _tail = Future<void>.value();

  int get revision => _revision;
  int begin() => ++_revision;
  bool isCurrent(int revision) => revision == _revision;

  Future<void> run(
    int revision,
    Future<void> Function(bool Function() isCurrent) operation,
  ) {
    final result = _tail.then((_) async {
      if (isCurrent(revision)) {
        await operation(() => isCurrent(revision));
      }
    });
    // One failure must not poison subsequent playback commands.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
