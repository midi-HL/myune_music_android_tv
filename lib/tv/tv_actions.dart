// Android TV 逻辑动作层。
//
// 三种物理输入（键盘 / 手柄 / 遥控器）先归一化成这里的逻辑动作，再由
// TvInputScope 分发给播放器或界面。物理键值不进入业务代码。

enum TvAction {
  none,
  playPause,
  nextTrack,
  previousTrack,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  toggleMute,
  togglePlayMode,
  openQueue,
  openPlayerPage,
  openAllSongs,
  openSettings,
  back,
}

const Map<TvAction, String> tvActionLabels = <TvAction, String>{
  TvAction.none: '不绑定',
  TvAction.playPause: '播放 / 暂停',
  TvAction.nextTrack: '下一首',
  TvAction.previousTrack: '上一首',
  TvAction.seekForward: '快进 5 秒',
  TvAction.seekBackward: '快退 5 秒',
  TvAction.volumeUp: '音量 +',
  TvAction.volumeDown: '音量 -',
  TvAction.toggleMute: '静音切换',
  TvAction.togglePlayMode: '切换播放模式',
  TvAction.openQueue: '打开播放队列',
  TvAction.openPlayerPage: '打开播放页',
  TvAction.openAllSongs: '打开全部歌曲',
  TvAction.openSettings: '打开设置',
  TvAction.back: '返回',
};

TvAction tvActionFromName(String? name) {
  if (name == null) return TvAction.none;
  for (final value in TvAction.values) {
    if (value.name == name) return value;
  }
  return TvAction.none;
}

enum TvInputSource { remote, gamepad, keyboard, unknown }

const Map<TvInputSource, String> tvInputSourceLabels = <TvInputSource, String>{
  TvInputSource.remote: '遥控器',
  TvInputSource.gamepad: '手柄',
  TvInputSource.keyboard: '键盘',
  TvInputSource.unknown: '未知',
};
