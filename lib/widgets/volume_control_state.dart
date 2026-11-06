import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'hover_overlay_control.dart';

class VolumeControl extends StatefulWidget {
  final Player player;
  final Color iconColor;
  final double size;

  const VolumeControl({
    required this.player,
    required this.iconColor,
    this.size = 24.0,
    super.key,
  });

  @override
  VolumeControlState createState() => VolumeControlState();
}

class VolumeControlState extends State<VolumeControl> {
  // 处理滚轮事件，增加/减少音量
  void _handleScroll(
    PointerSignalEvent event,
    PlaylistContentNotifier playlistNotifier,
  ) {
    if (event is PointerScrollEvent) {
      const double step = 3.0;
      final newVolume =
          (playlistNotifier.volume - event.scrollDelta.dy.sign * step).clamp(
            0.0,
            100.0,
          );
      playlistNotifier.setVolume(newVolume);
    }
  }

  // 获取当前应显示的音量图标
  IconData _getVolumeIcon(double volume) {
    if (volume < 1.0) return Icons.volume_off;
    if (volume <= 50.0) {
      return Icons.volume_down;
    }
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        return HoverOverlayControl(
          icon: _getVolumeIcon(playlistNotifier.volume),
          iconColor: widget.iconColor,
          size: widget.size,
          onIconPressed: playlistNotifier.toggleMute,
          onPointerSignal: (event) => _handleScroll(event, playlistNotifier),
          overlayOffset: const Offset(-12, -190),
          overlayConstraints: const BoxConstraints(
            maxWidth: 64,
            maxHeight: 220,
          ),
          overlayContentBuilder: (context) {
            return _buildOverlayContent();
          },
        );
      },
    );
  }

  Widget _buildOverlayContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 150,
            child: RotatedBox(
              quarterTurns: -1, // 横向滑块旋转成垂直显示
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 8,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: Consumer<PlaylistContentNotifier>(
                  builder: (context, notifier, child) {
                    return Slider(
                      value: notifier.volume,
                      min: 0,
                      max: 100,
                      onChanged: (value) {
                        notifier.setVolume(value);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Consumer<PlaylistContentNotifier>(
            builder: (context, notifier, child) {
              return Text(
                '${(notifier.volume).round()}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
