import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../layout/navigation_notifier.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/song_detail_page.dart';
import 'tv_actions.dart';
import 'tv_focus.dart';
import 'tv_key_map.dart';
import 'tv_navigation.dart';
import 'tv_settings.dart';

// TV 输入入口：把原生层广播的 Android 键值归一化成逻辑动作。
//
// 设计约束：
// 1. 方向键、DPAD_CENTER、字符输入一律放行给 Flutter，焦点遍历与打字
//    由框架负责，输入层不重复驱动，避免出现「一次按键跳两格」。
// 2. 手柄 A / ✕ 与遥控器 OK 不在这里处理（交给 Flutter 的确认链路）。
// 3. 未知键值记录到设置页，可手动绑定到任意逻辑动作，用来覆盖厂商
//    自定义遥控器 / 非标准键值。
class TvInputScope extends StatefulWidget {
  const TvInputScope({required this.child, super.key});

  final Widget child;

  @override
  State<TvInputScope> createState() => _TvInputScopeState();
}

class _TvInputScopeState extends State<TvInputScope> {
  static const EventChannel _events = EventChannel(
    'myune_music_android/input_events',
  );

  StreamSubscription<dynamic>? _subscription;
  TvSettings? _settings;
  DateTime _lastActionAt = DateTime.fromMillisecondsSinceEpoch(0);
  TvAction? _lastAction;

  @override
  void initState() {
    super.initState();
    _subscription = _events.receiveBroadcastStream().listen(
      _onKeyEvent,
      onError: (Object error) {
        // 通道不可用时静默降级为「纯焦点操作」，不打断应用。
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = context.read<TvSettings>();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onKeyEvent(dynamic raw) {
    if (raw is! Map) return;
    final settings = _settings;
    if (settings == null) return;

    final keyCode = (raw['keyCode'] as num?)?.toInt() ?? 0;
    final repeat = (raw['repeat'] as num?)?.toInt() ?? 0;
    final isGamepad = raw['isGamepad'] == true;
    final isKeyboard = raw['isKeyboard'] == true;
    final deviceName = (raw['deviceName'] as String?) ?? '';
    final source = isGamepad
        ? TvInputSource.gamepad
        : (isKeyboard ? TvInputSource.keyboard : TvInputSource.remote);

    // 只处理按下首帧；长按连发交给系统，避免音量/进度被重复事件推爆。
    if (repeat > 0) return;

    settings.noteInput(source: source, deviceName: deviceName);

    if (settings.learningMode) {
      settings.recordKey(
        keyCode: keyCode,
        deviceName: deviceName,
        source: source,
      );
      return;
    }

    // 文本输入场景下不劫持任何全局键（包括 Esc）。
    if (_isTextInputFocused()) return;

    final action = TvKeyMaps.resolve(
      keyCode: keyCode,
      source: source,
      custom: settings.customBindings,
    );

    if (action == null) {
      if (!TvKeyMaps.isKnown(keyCode)) {
        settings.recordKey(
          keyCode: keyCode,
          deviceName: deviceName,
          source: source,
        );
      }
      return;
    }

    final now = DateTime.now();
    if (_lastAction == action &&
        now.difference(_lastActionAt) < const Duration(milliseconds: 90)) {
      return;
    }
    _lastAction = action;
    _lastActionAt = now;
    _dispatch(action);
  }

  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null) return false;
    final widget = context.widget;
    if (widget is EditableText ||
        widget is TextField ||
        widget is TextFormField) {
      return true;
    }
    var isInput = false;
    context.visitAncestorElements((element) {
      final candidate = element.widget;
      if (candidate is EditableText ||
          candidate is TextField ||
          candidate is TextFormField) {
        isInput = true;
        return false;
      }
      if (candidate is Scaffold || candidate is Dialog) return false;
      return true;
    });
    return isInput;
  }

  void _dispatch(TvAction action) {
    final notifier = context.read<PlaylistContentNotifier>();
    final navigation = context.read<NavigationNotifier>();

    switch (action) {
      case TvAction.playPause:
        if (notifier.isPlaying) {
          notifier.pause();
        } else {
          notifier.play();
        }
        break;
      case TvAction.nextTrack:
        notifier.playNext();
        break;
      case TvAction.previousTrack:
        notifier.playPrevious();
        break;
      case TvAction.seekForward:
        notifier.mediaPlayer.seek(
          notifier.currentPosition + const Duration(seconds: 5),
        );
        break;
      case TvAction.seekBackward:
        notifier.mediaPlayer.seek(
          notifier.currentPosition - const Duration(seconds: 5),
        );
        break;
      case TvAction.volumeUp:
        notifier.setVolume((notifier.volume + 3).clamp(0.0, 100.0));
        break;
      case TvAction.volumeDown:
        notifier.setVolume((notifier.volume - 3).clamp(0.0, 100.0));
        break;
      case TvAction.toggleMute:
        notifier.toggleMute();
        break;
      case TvAction.togglePlayMode:
        notifier.togglePlayMode();
        break;
      case TvAction.openQueue:
        tvScaffoldKey.currentState?.openEndDrawer();
        break;
      case TvAction.openPlayerPage:
        tvRootNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => const SongDetailPage(),
          ),
        );
        break;
      case TvAction.openAllSongs:
        notifier.setActiveAllSongsView();
        navigation.navigateTo('/all_songs');
        break;
      case TvAction.openSettings:
        navigation.navigateTo('/settings');
        break;
      case TvAction.back:
        TvBackHandler.handle();
        break;
      case TvAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusTraversalGroup(child: widget.child);
  }
}
