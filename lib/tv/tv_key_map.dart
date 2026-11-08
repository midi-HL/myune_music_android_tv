import 'tv_actions.dart';

// Android KeyEvent 键值常量。只使用 AOSP 中稳定不变的公开数值。
// 不认识的厂商私有键值不会被丢弃：设置页的「按键学习」可以记录并绑定。
class AndroidKeyCode {
  static const int home = 3;
  static const int back = 4;
  static const int dpadUp = 19;
  static const int dpadDown = 20;
  static const int dpadLeft = 21;
  static const int dpadRight = 22;
  static const int dpadCenter = 23;
  static const int volumeUp = 24;
  static const int volumeDown = 25;
  static const int tab = 61;
  static const int space = 62;
  static const int enter = 66;
  static const int del = 67;
  static const int grave = 68;
  static const int minus = 69;
  static const int equals = 70;
  static const int leftBracket = 71;
  static const int rightBracket = 72;
  static const int backslash = 73;
  static const int semicolon = 74;
  static const int apostrophe = 75;
  static const int slash = 76;
  static const int menu = 82;
  static const int notification = 83;
  static const int search = 84;
  static const int mediaPlayPause = 85;
  static const int mediaStop = 86;
  static const int mediaNext = 87;
  static const int mediaPrevious = 88;
  static const int mediaRewind = 89;
  static const int mediaFastForward = 90;
  static const int pageUp = 92;
  static const int pageDown = 93;
  static const int escape = 111;
  static const int ctrlLeft = 113;
  static const int ctrlRight = 114;
  static const int shiftLeft = 59;
  static const int shiftRight = 60;
  static const int altLeft = 57;
  static const int altRight = 58;
  static const int moveHome = 122;
  static const int moveEnd = 123;
  static const int mediaPlay = 126;
  static const int mediaPause = 127;
  static const int mediaClose = 128;
  static const int mediaEject = 129;
  static const int mediaRecord = 130;
  static const int numpad0 = 144;
  static const int numpad2 = 146;
  static const int numpad4 = 148;
  static const int numpad6 = 150;
  static const int numpad8 = 152;
  static const int volumeMute = 164;
  static const int channelUp = 166;
  static const int channelDown = 167;
  static const int zoomIn = 168;
  static const int zoomOut = 169;
  static const int tv = 170;
  static const int info = 171;
  static const int guide = 172;
  static const int dvr = 173;
  static const int bookmark = 174;
  static const int captions = 175;
  static const int settings = 176;
  static const int appSwitch = 181;
  static const int progRed = 183;
  static const int progGreen = 184;
  static const int progYellow = 185;
  static const int progBlue = 186;
  static const int lastChannel = 229;
  static const int f1 = 131;
  static const int f11 = 141;
  static const int f12 = 142;

  // 手柄按「物理位置」统一：Xbox 的 A/B/X/Y 与 PlayStation 的 ✕/○/□/△
  // 在 Android 上都上报 BUTTON_A/B/X/Y，因此同一套映射即可覆盖两种手柄。
  static const int buttonA = 96;
  static const int buttonB = 97;
  static const int buttonC = 98;
  static const int buttonX = 99;
  static const int buttonY = 100;
  static const int buttonZ = 101;
  static const int buttonL1 = 102;
  static const int buttonR1 = 103;
  static const int buttonL2 = 104;
  static const int buttonR2 = 105;
  static const int buttonThumbL = 106;
  static const int buttonThumbR = 107;
  static const int buttonStart = 108;
  static const int buttonSelect = 109;
  static const int buttonMode = 110;
  static const int button1 = 188;
  static const int button16 = 203;

  // 物理键盘字母：A=29 ... Z=54（AOSP 连续段）。
  static const int keyA = 29;
  static const int keyB = 30;
  static const int keyC = 31;
  static const int keyD = 32;
  static const int keyE = 33;
  static const int keyF = 34;
  static const int keyG = 35;
  static const int keyH = 36;
  static const int keyI = 37;
  static const int keyJ = 38;
  static const int keyK = 39;
  static const int keyL = 40;
  static const int keyM = 41;
  static const int keyN = 42;
  static const int keyO = 43;
  static const int keyP = 44;
  static const int keyQ = 45;
  static const int keyR = 46;
  static const int keyS = 47;
  static const int keyT = 48;
  static const int keyU = 49;
  static const int keyV = 50;
  static const int keyW = 51;
  static const int keyX = 52;
  static const int keyY = 53;
  static const int keyZ = 54;
  static const int comma = 55;
  static const int period = 56;
  static const int digit0 = 7;
  static const int digit9 = 16;
}

final Map<int, TvAction> _mediaKeys = <int, TvAction>{
  AndroidKeyCode.mediaPlayPause: TvAction.playPause,
  AndroidKeyCode.mediaPlay: TvAction.playPause,
  AndroidKeyCode.mediaPause: TvAction.playPause,
  AndroidKeyCode.mediaStop: TvAction.playPause,
  AndroidKeyCode.mediaNext: TvAction.nextTrack,
  AndroidKeyCode.mediaPrevious: TvAction.previousTrack,
  AndroidKeyCode.mediaRewind: TvAction.seekBackward,
  AndroidKeyCode.mediaFastForward: TvAction.seekForward,
  AndroidKeyCode.volumeUp: TvAction.volumeUp,
  AndroidKeyCode.volumeDown: TvAction.volumeDown,
  AndroidKeyCode.volumeMute: TvAction.toggleMute,
};

class TvKeyMaps {
  TvKeyMaps._();

  // 遥控器：带媒体键的遥控器走全局快捷键；不带媒体键的遥控器靠
  // 方向键 + OK 的焦点控件同样可以完成全部操作，这里只是加速键。
  static final Map<int, TvAction> remote = <int, TvAction>{
    ..._mediaKeys,
    AndroidKeyCode.menu: TvAction.openQueue,
    AndroidKeyCode.guide: TvAction.openQueue,
    AndroidKeyCode.info: TvAction.openPlayerPage,
    AndroidKeyCode.settings: TvAction.openSettings,
    AndroidKeyCode.search: TvAction.openAllSongs,
    AndroidKeyCode.progRed: TvAction.playPause,
    AndroidKeyCode.progGreen: TvAction.nextTrack,
    AndroidKeyCode.progYellow: TvAction.previousTrack,
    AndroidKeyCode.progBlue: TvAction.openQueue,
    AndroidKeyCode.bookmark: TvAction.togglePlayMode,
  };

  // 手柄：A / ✕ 保留给 Flutter 焦点系统做「确认」，避免与 DPAD_CENTER 双跳。
  static final Map<int, TvAction> gamepad = <int, TvAction>{
    ..._mediaKeys,
    AndroidKeyCode.buttonB: TvAction.back,
    AndroidKeyCode.buttonStart: TvAction.playPause,
    AndroidKeyCode.buttonSelect: TvAction.openQueue,
    AndroidKeyCode.buttonX: TvAction.openPlayerPage,
    AndroidKeyCode.buttonY: TvAction.toggleMute,
    AndroidKeyCode.buttonL1: TvAction.previousTrack,
    AndroidKeyCode.buttonR1: TvAction.nextTrack,
    AndroidKeyCode.buttonL2: TvAction.seekBackward,
    AndroidKeyCode.buttonR2: TvAction.seekForward,
    AndroidKeyCode.buttonMode: TvAction.openSettings,
    AndroidKeyCode.buttonZ: TvAction.togglePlayMode,
  };

  // 键盘：方向键专职焦点遍历，因此桌面端的 ←→ 快退/快进、↑↓ 音量
  // 在 TV 分支改用功能键；Space / Enter 保留给 Flutter 做「激活」。
  static final Map<int, TvAction> keyboard = <int, TvAction>{
    ..._mediaKeys,
    AndroidKeyCode.keyP: TvAction.playPause,
    AndroidKeyCode.leftBracket: TvAction.previousTrack,
    AndroidKeyCode.rightBracket: TvAction.nextTrack,
    AndroidKeyCode.comma: TvAction.seekBackward,
    AndroidKeyCode.period: TvAction.seekForward,
    AndroidKeyCode.minus: TvAction.volumeDown,
    AndroidKeyCode.equals: TvAction.volumeUp,
    AndroidKeyCode.keyM: TvAction.toggleMute,
    AndroidKeyCode.keyQ: TvAction.openQueue,
    AndroidKeyCode.keyF: TvAction.openAllSongs,
    AndroidKeyCode.keyG: TvAction.openSettings,
    AndroidKeyCode.keyO: TvAction.togglePlayMode,
    AndroidKeyCode.f11: TvAction.openPlayerPage,
    AndroidKeyCode.numpad2: TvAction.volumeDown,
    AndroidKeyCode.numpad8: TvAction.volumeUp,
    AndroidKeyCode.numpad4: TvAction.seekBackward,
    AndroidKeyCode.numpad6: TvAction.seekForward,
    AndroidKeyCode.escape: TvAction.back,
    AndroidKeyCode.menu: TvAction.openQueue,
    AndroidKeyCode.settings: TvAction.openSettings,
  };

  // 已知但不产生逻辑动作的键：交给 Flutter 的焦点系统 / 文本输入链路。
  // 这些键不会出现在「未识别按键」列表里。
  static final Set<int> _passThrough = <int>{
    AndroidKeyCode.home,
    AndroidKeyCode.back,
    AndroidKeyCode.dpadUp,
    AndroidKeyCode.dpadDown,
    AndroidKeyCode.dpadLeft,
    AndroidKeyCode.dpadRight,
    AndroidKeyCode.dpadCenter,
    AndroidKeyCode.enter,
    AndroidKeyCode.space,
    AndroidKeyCode.tab,
    AndroidKeyCode.del,
    AndroidKeyCode.escape,
    AndroidKeyCode.ctrlLeft,
    AndroidKeyCode.ctrlRight,
    AndroidKeyCode.shiftLeft,
    AndroidKeyCode.shiftRight,
    AndroidKeyCode.altLeft,
    AndroidKeyCode.altRight,
    AndroidKeyCode.pageUp,
    AndroidKeyCode.pageDown,
    AndroidKeyCode.moveHome,
    AndroidKeyCode.moveEnd,
    AndroidKeyCode.channelUp,
    AndroidKeyCode.channelDown,
    AndroidKeyCode.tv,
    AndroidKeyCode.appSwitch,
    AndroidKeyCode.notification,
    AndroidKeyCode.buttonA,
    AndroidKeyCode.buttonC,
    AndroidKeyCode.buttonThumbL,
    AndroidKeyCode.buttonThumbR,
    AndroidKeyCode.button1,
    AndroidKeyCode.button16,
    ...List<int>.generate(26, (int i) => AndroidKeyCode.keyA + i),
    ...List<int>.generate(10, (int i) => AndroidKeyCode.digit0 + i),
    ...List<int>.generate(16, (int i) => AndroidKeyCode.numpad0 + i),
  };

  static bool isKnown(int keyCode) {
    if (_passThrough.contains(keyCode)) return true;
    if (remote.containsKey(keyCode)) return true;
    if (gamepad.containsKey(keyCode)) return true;
    if (keyboard.containsKey(keyCode)) return true;
    if (keyCode >= AndroidKeyCode.button1 &&
        keyCode <= AndroidKeyCode.button16) {
      return true;
    }
    return false;
  }

  static TvAction? resolve({
    required int keyCode,
    required TvInputSource source,
    required Map<int, TvAction> custom,
  }) {
    final override = custom[keyCode];
    if (override != null) {
      return override == TvAction.none ? null : override;
    }
    switch (source) {
      case TvInputSource.gamepad:
        return gamepad[keyCode] ?? _mediaKeys[keyCode] ?? remote[keyCode];
      case TvInputSource.keyboard:
        return keyboard[keyCode] ?? _mediaKeys[keyCode] ?? remote[keyCode];
      case TvInputSource.remote:
      case TvInputSource.unknown:
        return remote[keyCode] ?? _mediaKeys[keyCode];
    }
  }

  static const Map<int, String> keyLabels = <int, String>{
    AndroidKeyCode.back: '返回',
    AndroidKeyCode.dpadCenter: 'OK / 确认',
    AndroidKeyCode.dpadUp: '方向键上',
    AndroidKeyCode.dpadDown: '方向键下',
    AndroidKeyCode.dpadLeft: '方向键左',
    AndroidKeyCode.dpadRight: '方向键右',
    AndroidKeyCode.menu: '菜单',
    AndroidKeyCode.mediaPlayPause: '媒体播放/暂停',
    AndroidKeyCode.mediaPlay: '媒体播放',
    AndroidKeyCode.mediaPause: '媒体暂停',
    AndroidKeyCode.mediaNext: '媒体下一首',
    AndroidKeyCode.mediaPrevious: '媒体上一首',
    AndroidKeyCode.mediaRewind: '媒体快退',
    AndroidKeyCode.mediaFastForward: '媒体快进',
    AndroidKeyCode.volumeUp: '音量 +',
    AndroidKeyCode.volumeDown: '音量 -',
    AndroidKeyCode.volumeMute: '静音',
    AndroidKeyCode.space: '空格',
    AndroidKeyCode.enter: '回车',
    AndroidKeyCode.escape: 'Esc',
    AndroidKeyCode.keyP: 'P',
    AndroidKeyCode.keyQ: 'Q',
    AndroidKeyCode.keyF: 'F',
    AndroidKeyCode.keyG: 'G',
    AndroidKeyCode.keyM: 'M',
    AndroidKeyCode.keyO: 'O',
    AndroidKeyCode.comma: ',',
    AndroidKeyCode.period: '.',
    AndroidKeyCode.minus: '-',
    AndroidKeyCode.equals: '=',
    AndroidKeyCode.leftBracket: '[',
    AndroidKeyCode.rightBracket: ']',
    AndroidKeyCode.buttonA: '手柄 A / ✕',
    AndroidKeyCode.buttonB: '手柄 B / ○',
    AndroidKeyCode.buttonX: '手柄 X / □',
    AndroidKeyCode.buttonY: '手柄 Y / △',
    AndroidKeyCode.buttonL1: 'L1 / LB',
    AndroidKeyCode.buttonR1: 'R1 / RB',
    AndroidKeyCode.buttonL2: 'L2 / LT',
    AndroidKeyCode.buttonR2: 'R2 / RT',
    AndroidKeyCode.buttonStart: 'Start / Options',
    AndroidKeyCode.buttonSelect: 'Select / Share',
    AndroidKeyCode.buttonMode: 'Guide / PS',
    AndroidKeyCode.guide: 'Guide',
    AndroidKeyCode.info: 'Info',
    AndroidKeyCode.settings: 'Settings',
    AndroidKeyCode.search: 'Search',
    AndroidKeyCode.progRed: '红色键',
    AndroidKeyCode.progGreen: '绿色键',
    AndroidKeyCode.progYellow: '黄色键',
    AndroidKeyCode.progBlue: '蓝色键',
  };

  static String describe(int keyCode) =>
      keyLabels[keyCode] ?? '键值 $keyCode';
}
