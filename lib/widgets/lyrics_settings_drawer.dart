import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../page/setting/settings_provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/network/tv_network_widgets.dart';
import '../lyrics/lyric_source.dart';
import "../page/setting/tabs/info_icon.dart";
import '../tv/tv_device.dart';
import '../tv/tv_focus_nav.dart';

class LyricsSettingsDrawer extends StatelessWidget {
  const LyricsSettingsDrawer({super.key});

  /// 播放页「歌词选择」：本次临时切换歌词来源，立即重新加载并生效。
  /// 不写任何持久化设置，设置页里的「歌词来源优先级」保持原样。
  static Future<void> _selectLyric(
    BuildContext context,
    LyricSource source,
    String label, {
    bool refreshOnline = false,
  }) async {
    await context.read<PlaylistContentNotifier>().selectLyricSource(
      source,
      refreshOnline: refreshOnline,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已切换为$label'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static String _fontWeightLabel(int weight) {
    const Map<int, String> names = {
      100: '极细',
      200: '特细',
      300: '细体',
      400: '常规',
      500: '中等',
      600: '半粗',
      700: '粗体',
      800: '特粗',
      900: '极粗',
    };
    final String name = names[weight] ?? '自定义';
    return '$name $weight';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Drawer(
      // 10-foot UI：电视上把抽屉加宽，避免滑块与分段按钮挤在窄条里。
      width: TvDevice.isTv ? 420 : null,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '歌词显示设置',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      tooltip: '关闭',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // 歌词对齐方式设置
                Text('歌词对齐方式', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TextAlign>(
                    segments: const [
                      ButtonSegment(value: TextAlign.left, label: Text('居左')),
                      ButtonSegment(value: TextAlign.center, label: Text('居中')),
                      ButtonSegment(value: TextAlign.right, label: Text('居右')),
                    ],
                    selected: {settings.lyricAlignment},
                    onSelectionChanged: (Set<TextAlign> newSelection) {
                      if (newSelection.isNotEmpty) {
                        context.read<SettingsProvider>().setLyricAlignment(
                          newSelection.first,
                        );
                      }
                    },
                    showSelectedIcon: false,
                  ),
                ),
                const Divider(),

                // 同时间戳歌词行数设置
                Text(
                  '同时间戳歌词行数',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: List.generate(5, (index) {
                    final value = index + 1;
                    return ButtonSegment(value: value, label: Text('$value'));
                  }),
                  selected: {settings.maxLinesPerLyric},
                  onSelectionChanged: (newSelection) {
                    final value = newSelection.first;
                    context.read<SettingsProvider>().setMaxLinesPerLyric(value);
                  },
                  showSelectedIcon: false,
                ),
                const Divider(),

                // 歌词字体大小设置
                Text('歌词字体大小', style: Theme.of(context).textTheme.titleMedium),
                Tooltip(
                  message: settings.autoAdjustLyricLayout
                      ? '已启用 "自动调节歌词字体与间距" '
                      : '',
                  child: IgnorePointer(
                    ignoring: settings.autoAdjustLyricLayout,
                    child: Opacity(
                      opacity: settings.autoAdjustLyricLayout ? 0.5 : 1.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TvAdjustableSlider(
                            value: settings.fontSize,
                            min: 12.0,
                            max: 32.0,
                            divisions: 20,
                            onChanged: (value) {
                              context.read<SettingsProvider>().setFontSize(
                                value,
                              );
                            },
                            child: Slider(
                              value: settings.fontSize,
                              min: 12.0,
                              max: 32.0,
                              divisions: 20,
                              label: settings.fontSize.toStringAsFixed(1),
                              onChanged: (value) {
                                context.read<SettingsProvider>().setFontSize(
                                  value,
                                );
                              },
                            ),
                          ),
                          Text(
                            '当前大小: ${settings.fontSize.toStringAsFixed(1)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(),

                // 歌词字重设置（高亮行与非高亮行统一使用）
                Row(
                  children: [
                    Text(
                      '歌词字重',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 4),
                    const InfoIcon('使用自定义字体时，需要字体支持对应的字重'),
                  ],
                ),

                const SizedBox(height: 4),
                TvAdjustableSlider(
                  value: settings.lyricFontWeight.toDouble(),
                  min: 100,
                  max: 900,
                  divisions: 16,
                  onChanged: (value) {
                    context.read<SettingsProvider>().setLyricFontWeight(
                      value.round(),
                    );
                  },
                  child: Slider(
                    value: settings.lyricFontWeight.toDouble(),
                    min: 100,
                    max: 900,
                    divisions: 16,
                    label: _fontWeightLabel(settings.lyricFontWeight),
                    onChanged: (value) {
                      context.read<SettingsProvider>().setLyricFontWeight(
                        value.round(),
                      );
                    },
                  ),
                ),
                Text(
                  '当前字重: ${_fontWeightLabel(settings.lyricFontWeight)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Divider(),

                // 歌词垂直间距设置
                Text('歌词垂直间距', style: Theme.of(context).textTheme.titleMedium),
                Tooltip(
                  message: settings.autoAdjustLyricLayout
                      ? '已启用 "自动调节歌词字体与间距" '
                      : '',
                  child: IgnorePointer(
                    ignoring: settings.autoAdjustLyricLayout,
                    child: Opacity(
                      opacity: settings.autoAdjustLyricLayout ? 0.5 : 1.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TvAdjustableSlider(
                            value: settings.lyricVerticalSpacing,
                            min: 0.0,
                            max: 20.0,
                            divisions: 20,
                            onChanged: (value) {
                              context
                                  .read<SettingsProvider>()
                                  .setLyricVerticalSpacing(value);
                            },
                            child: Slider(
                              value: settings.lyricVerticalSpacing,
                              min: 0.0,
                              max: 20.0,
                              divisions: 20,
                              label: settings.lyricVerticalSpacing
                                  .toStringAsFixed(1),
                              onChanged: (value) {
                                context
                                    .read<SettingsProvider>()
                                    .setLyricVerticalSpacing(value);
                              },
                            ),
                          ),
                          Text(
                            '当前间距: ${settings.lyricVerticalSpacing.toStringAsFixed(1)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(),

                // 歌词模糊强度设置
                Text('歌词模糊强度', style: Theme.of(context).textTheme.titleMedium),
                Tooltip(
                  message: settings.enableLyricBlur ? '' : '需启用 "歌词模糊效果" ',
                  child: IgnorePointer(
                    ignoring: !settings.enableLyricBlur,
                    child: Opacity(
                      opacity: settings.enableLyricBlur ? 1.0 : 0.5,
                      child: TvAdjustableSlider(
                        value: settings.lyricBlurStrength,
                        min: 1.0,
                        max: 4.0,
                        divisions: 12,
                        onChanged: (value) {
                          context
                              .read<SettingsProvider>()
                              .setLyricBlurStrength(value);
                        },
                        child: Slider(
                          value: settings.lyricBlurStrength,
                          min: 1.0,
                          max: 4.0,
                          divisions: 12,
                          label: settings.lyricBlurStrength.toStringAsFixed(1),
                          onChanged: (value) {
                            context
                                .read<SettingsProvider>()
                                .setLyricBlurStrength(value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  '当前强度: ${settings.lyricBlurStrength.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Divider(),

                // Text('歌词高亮位置', style: Theme.of(context).textTheme.titleMedium),
                // Slider(
                //   value: settings.lyricHighlightPosition,
                //   min: 0.0,
                //   max: 1.0,
                //   divisions: 10,
                //   label: settings.lyricHighlightPosition.toStringAsFixed(1),
                //   onChanged: (value) {
                //     context.read<SettingsProvider>().setLyricHighlightPosition(
                //       value,
                //     );
                //   },
                // ),
                // Text(
                //   '当前位置: ${settings.lyricHighlightPosition.toStringAsFixed(1)}',
                //   style: Theme.of(context).textTheme.bodyMedium,
                // ),

                // ===== 歌词选择（电视简化）=====
                // 只追加在播放页歌词设置的下面；上面所有原有设置项保持原样，
                // 设置页里的「歌词来源优先级」6 项排序也完全不动。
                // 选中即实时生效，不写任何持久化设置。
                const Divider(),
                Text(
                  '歌词选择',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '选择后立即生效，不会改动设置页里的来源优先级',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                TvActionButton(
                  label: '网络歌词',
                  value: '在线搜索',
                  icon: Icons.cloud_outlined,
                  onPressed: () => _selectLyric(
                    context,
                    LyricSource.online,
                    '网络歌词',
                  ),
                ),
                const SizedBox(height: 8),
                TvActionButton(
                  label: '内嵌歌词',
                  value: '音频文件标签',
                  icon: Icons.audiotrack_outlined,
                  onPressed: () => _selectLyric(
                    context,
                    LyricSource.embedded,
                    '内嵌歌词',
                  ),
                ),
                const SizedBox(height: 8),
                TvActionButton(
                  label: '外置文件',
                  value: '自动识别所有格式',
                  icon: Icons.insert_drive_file_outlined,
                  onPressed: () => _selectLyric(
                    context,
                    LyricSource.externalLrc,
                    '外置文件',
                  ),
                ),
                const SizedBox(height: 8),
                TvActionButton(
                  label: '从网上获取新歌词',
                  value: '重新搜索',
                  icon: Icons.refresh,
                  onPressed: () => _selectLyric(
                    context,
                    LyricSource.online,
                    '在线歌词',
                    refreshOnline: true,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '外置文件会自动尝试 .lrc / .krc / .qrc / .yrc 等，'
                  '目录里有什么格式就用什么格式',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
