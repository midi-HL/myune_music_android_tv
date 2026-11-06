import 'package:flutter/services.dart';

class AndroidUiScaleChannel {
  static const MethodChannel _channel = MethodChannel('myune_music_android/ui_scale');

  static Future<void> setScale(double scale) async {
    try {
      await _channel.invokeMethod<void>('setScale', <String, double>{'scale': scale});
    } on MissingPluginException {
      // Desktop and older runners keep the system density.
    } on PlatformException {
      // Retried on the next resume.
    }
  }
}
