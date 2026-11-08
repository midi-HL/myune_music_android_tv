import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_actions.dart';
import 'tv_gamepad_icons.dart';

class TvLearnedKey {
  const TvLearnedKey({
    required this.keyCode,
    required this.deviceName,
    required this.source,
    this.count = 1,
  });

  final int keyCode;
  final String deviceName;
  final TvInputSource source;
  final int count;

  TvLearnedKey withIncrement() => TvLearnedKey(
    keyCode: keyCode,
    deviceName: deviceName,
    source: source,
    count: count + 1,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'keyCode': keyCode,
    'deviceName': deviceName,
    'source': source.name,
    'count': count,
  };

  static TvLearnedKey fromJson(Map<String, dynamic> json) => TvLearnedKey(
    keyCode: (json['keyCode'] as num?)?.toInt() ?? 0,
    deviceName: (json['deviceName'] as String?) ?? '',
    source: tvInputSourceFromName(json['source'] as String?),
    count: (json['count'] as num?)?.toInt() ?? 1,
  );
}

TvInputSource tvInputSourceFromName(String? name) {
  for (final value in TvInputSource.values) {
    if (value.name == name) return value;
  }
  return TvInputSource.unknown;
}

class TvSettings extends ChangeNotifier {
  static const _gamepadIconKey = 'tv_gamepad_icon_style';
  static const _uiScaleKey = 'tv_ui_scale';
  static const _mediaKeysKey = 'tv_remote_has_media_keys';
  static const _bindingsKey = 'tv_key_bindings';
  static const _learnedKey = 'tv_learned_keys';

  TvSettings() {
    initializationFuture = load();
  }

  late final Future<void> initializationFuture;

  TvGamepadIconStyle _gamepadIconStyle = TvGamepadIconStyle.auto;
  double _uiScale = 1.0;
  bool _remoteHasMediaKeys = true;
  bool _learningMode = false;
  Map<int, TvAction> _customBindings = <int, TvAction>{};
  List<TvLearnedKey> _learnedKeys = <TvLearnedKey>[];
  TvInputSource _lastInputSource = TvInputSource.unknown;
  String _lastDeviceName = '';

  TvGamepadIconStyle get gamepadIconStyle => _gamepadIconStyle;
  double get uiScale => _uiScale;
  bool get remoteHasMediaKeys => _remoteHasMediaKeys;
  bool get learningMode => _learningMode;
  Map<int, TvAction> get customBindings => _customBindings;
  List<TvLearnedKey> get learnedKeys => _learnedKeys;
  TvInputSource get lastInputSource => _lastInputSource;
  String get lastDeviceName => _lastDeviceName;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _gamepadIconStyle = tvGamepadIconStyleFromName(
        prefs.getString(_gamepadIconKey),
      );
      _uiScale = (prefs.getDouble(_uiScaleKey) ?? 1.0).clamp(0.8, 1.3);
      _remoteHasMediaKeys = prefs.getBool(_mediaKeysKey) ?? true;

      final bindingsRaw = prefs.getString(_bindingsKey);
      if (bindingsRaw != null && bindingsRaw.isNotEmpty) {
        final decoded = jsonDecode(bindingsRaw);
        if (decoded is Map) {
          _customBindings = <int, TvAction>{};
          decoded.forEach((dynamic key, dynamic value) {
            final code = int.tryParse(key.toString());
            if (code == null) return;
            final action = tvActionFromName(value as String?);
            if (action != TvAction.none) {
              _customBindings[code] = action;
            }
          });
        }
      }

      final learnedRaw = prefs.getString(_learnedKey);
      if (learnedRaw != null && learnedRaw.isNotEmpty) {
        final decoded = jsonDecode(learnedRaw);
        if (decoded is List) {
          _learnedKeys = decoded
              .whereType<Map>()
              .map(
                (dynamic item) =>
                    TvLearnedKey.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();
        }
      }
      notifyListeners();
    } catch (_) {
      // 读取失败时保持默认值，不让 TV 设置阻断应用启动。
    }
  }

  void noteInput({required TvInputSource source, required String deviceName}) {
    final changed = source != _lastInputSource ||
        (deviceName.isNotEmpty && deviceName != _lastDeviceName);
    _lastInputSource = source;
    if (deviceName.isNotEmpty) _lastDeviceName = deviceName;
    if (changed) notifyListeners();
  }

  Future<void> setGamepadIconStyle(TvGamepadIconStyle value) async {
    _gamepadIconStyle = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gamepadIconKey, value.name);
  }

  Future<void> setUiScale(double value) async {
    _uiScale = value.clamp(0.8, 1.3);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, _uiScale);
  }

  Future<void> setRemoteHasMediaKeys(bool value) async {
    _remoteHasMediaKeys = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mediaKeysKey, value);
  }

  void setLearningMode(bool value) {
    _learningMode = value;
    notifyListeners();
  }

  Future<void> bindKey(int keyCode, TvAction action) async {
    if (action == TvAction.none) {
      _customBindings.remove(keyCode);
    } else {
      _customBindings = <int, TvAction>{..._customBindings, keyCode: action};
    }
    notifyListeners();
    await _saveBindings();
  }

  Future<void> resetBindings() async {
    _customBindings = <int, TvAction>{};
    notifyListeners();
    await _saveBindings();
  }

  Future<void> _saveBindings() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, String>{
      for (final entry in _customBindings.entries)
        entry.key.toString(): entry.value.name,
    };
    await prefs.setString(_bindingsKey, jsonEncode(encoded));
  }

  Future<void> recordKey({
    required int keyCode,
    required String deviceName,
    required TvInputSource source,
  }) async {
    final index = _learnedKeys.indexWhere((k) => k.keyCode == keyCode);
    if (index >= 0) {
      final updated = _learnedKeys[index].withIncrement();
      _learnedKeys = <TvLearnedKey>[
        ..._learnedKeys.sublist(0, index),
        updated,
        ..._learnedKeys.sublist(index + 1),
      ];
    } else {
      _learnedKeys = <TvLearnedKey>[
        ..._learnedKeys,
        TvLearnedKey(
          keyCode: keyCode,
          deviceName: deviceName,
          source: source,
        ),
      ];
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _learnedKey,
      jsonEncode(_learnedKeys.map((k) => k.toJson()).toList()),
    );
  }

  Future<void> clearLearnedKeys() async {
    _learnedKeys = <TvLearnedKey>[];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_learnedKey);
  }
}
