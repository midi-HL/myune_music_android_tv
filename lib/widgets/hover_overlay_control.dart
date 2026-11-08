import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../tv/tv_device.dart';
import '../tv/tv_focus_nav.dart';

class HoverOverlayControl extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final WidgetBuilder overlayContentBuilder;
  final VoidCallback? onIconPressed;
  final void Function(PointerSignalEvent)? onPointerSignal;
  final BoxConstraints overlayConstraints;
  final Offset overlayOffset;

  final double size;

  const HoverOverlayControl({
    required this.icon,
    required this.iconColor,
    required this.overlayContentBuilder,
    required this.overlayOffset,
    this.onIconPressed,
    this.onPointerSignal,
    this.overlayConstraints = const BoxConstraints(maxWidth: 240),
    this.size = 24.0,
    super.key,
  });

  @override
  HoverOverlayControlState createState() => HoverOverlayControlState();
}

class HoverOverlayControlState extends State<HoverOverlayControl> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;
  late final VoidCallback _closeCallback;

  @override
  void initState() {
    super.initState();
    _closeCallback = _removeOverlay;
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          offset: widget.overlayOffset,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: widget.overlayConstraints,
              child: MouseRegion(
                onEnter: (_) => _setHovering(true),
                onExit: (_) => _setHovering(false),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: widget.overlayContentBuilder(context),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
    // 返回键优先关闭浮层，而不是直接退页面 / 退出应用。
    TvOverlayRegistry.instance.add(_closeCallback);
    if (TvDevice.isTv) {
      TvFocusController.instance.scheduleFocusWhere(
        (context) =>
            context.widget is Slider ||
            context.findAncestorWidgetOfExactType<Slider>() != null,
      );
    }
  }

  void _removeOverlay() {
    TvOverlayRegistry.instance.remove(_closeCallback);
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _setHovering(bool hovering) {
    if (!mounted) return;
    // Android 上浮层由点击展开，不能因 MouseRegion 的离开事件自动消失。
    if (Platform.isAndroid) return;
    _isHovering = hovering;
    if (!hovering) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isHovering) _removeOverlay();
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            widget.onPointerSignal?.call(event);
            _overlayEntry?.markNeedsBuild();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            if (Platform.isAndroid) return;
            _setHovering(true);
            _showOverlay();
          },
          onExit: (_) => _setHovering(false),
          child: IconButton(
            iconSize: widget.size,
            icon: Icon(
              widget.icon,
              color: widget.iconColor.withAlpha(179),
              size: widget.size,
            ),
            onPressed: () {
              final hasExternal = widget.onIconPressed != null;
              if (!Platform.isAndroid) {
                if (hasExternal) {
                  widget.onIconPressed!();
                  _overlayEntry?.markNeedsBuild();
                } else if (_overlayEntry == null) {
                  _showOverlay();
                } else {
                  _removeOverlay();
                }
                return;
              }
              // 触屏 / TV 遥控器：第一次按键展开浮层并自动聚焦竖条。
              if (_overlayEntry == null) {
                _showOverlay();
                return;
              }
              if (hasExternal) {
                widget.onIconPressed!();
              }
              _removeOverlay();
            },
          ),
        ),
      ),
    );
  }
}
