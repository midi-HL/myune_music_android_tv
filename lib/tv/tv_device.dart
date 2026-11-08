import 'package:flutter/services.dart';

// 由 ci/MainActivity.kt 的 getDeviceInfo 提供。任何异常都降级为「非 TV」，
// 保证手机端与尚未注入原生通道的旧包行为完全不变。
class TvDevice {
  TvDevice._();

  static const MethodChannel _channel = MethodChannel(
    'myune_music_android/device',
  );

  static bool initialized = false;
  static bool isTv = false;
  static bool hasLeanback = false;
  static bool hasTelevisionFeature = false;
  static bool hasTouchscreen = true;
  static bool uiModeTypeTelevision = false;
  static int sdkInt = 0;

  static Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'getDeviceInfo',
      );
      if (info == null) return;
      isTv = info['isTv'] == true;
      hasLeanback = info['hasLeanback'] == true;
      hasTelevisionFeature = info['hasTelevisionFeature'] == true;
      hasTouchscreen = info['hasTouchscreen'] != false;
      uiModeTypeTelevision = info['uiModeTypeTelevision'] == true;
      sdkInt = (info['sdkInt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // MissingPluginException 等情况：按普通 Android 设备处理。
      isTv = false;
    }
  }

  static String get summary {
    if (!initialized) return '未初始化';
    if (!isTv) return '普通 Android 设备';
    final flags = <String>[
      if (hasLeanback) 'leanback',
      if (hasTelevisionFeature) 'television',
      if (uiModeTypeTelevision) 'uiMode=TV',
      if (!hasTouchscreen) '无触摸屏',
    ];
    return 'Android TV (SDK $sdkInt${flags.isEmpty ? '' : ', ${flags.join(', ')}'})';
  }
}
