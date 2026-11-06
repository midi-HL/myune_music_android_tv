import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/android_ui_scale_channel.dart';

class AndroidUiScaler extends StatefulWidget {
  const AndroidUiScaler({required this.child, required this.scale, super.key});

  final Widget child;
  final double scale;

  @override
  State<AndroidUiScaler> createState() => _AndroidUiScalerState();
}

class _AndroidUiScalerState extends State<AndroidUiScaler> with WidgetsBindingObserver {
  double? _appliedScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncScale();
  }

  @override
  void didUpdateWidget(AndroidUiScaler oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncScale();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncScale(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncScale({bool force = false}) {
    if (!Platform.isAndroid) return;
    final scale = widget.scale.clamp(0.55, 1.0);
    if (!force && _appliedScale == scale) return;
    _appliedScale = scale;
    AndroidUiScaleChannel.setScale(scale);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
