import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'tv_actions.dart';
import 'tv_device.dart';
import 'tv_gamepad_icons.dart';
import 'tv_key_map.dart';
import 'tv_focus_nav.dart';
import 'tv_settings.dart';

class TvSettingsTab extends StatelessWidget {
  const TvSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TvSettings>();
    final effectiveStyle = resolveGamepadIconStyle(
      settings.gamepadIconStyle,
      settings.lastDeviceName,
    );

    return ListView(
      key: const ValueKey('tv_settings'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: <Widget>[
        _SectionCard(
          title: '设备',
          children: <Widget>[
            ListTile(
              dense: true,
              leading: const Icon(Icons.tv_outlined),
              title: Text(TvDevice.summary),
              subtitle: Text(
                settings.lastDeviceName.isEmpty
                    ? '尚未检测到输入设备按键'
                    : '最近输入：${tvInputSourceLabels[settings.lastInputSource]} · ${settings.lastDeviceName}',
              ),
            ),
          ],
        ),
        _SectionCard(
          title: '手柄图标',
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Xbox 与 PlayStation 手柄共用同一套按键映射，这里只切换界面上显示的按钮图标。',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<TvGamepadIconStyle>(
                segments: <ButtonSegment<TvGamepadIconStyle>>[
                  for (final style in TvGamepadIconStyle.values)
                    ButtonSegment<TvGamepadIconStyle>(
                      value: style,
                      label: Text(tvGamepadIconStyleLabels[style] ?? style.name),
                    ),
                ],
                selected: <TvGamepadIconStyle>{settings.gamepadIconStyle},
                showSelectedIcon: false,
                onSelectionChanged: (Set<TvGamepadIconStyle> selection) {
                  if (selection.isNotEmpty) {
                    settings.setGamepadIconStyle(selection.first);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 14,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final button in <TvGamepadButton>[
                    TvGamepadButton.a,
                    TvGamepadButton.b,
                    TvGamepadButton.x,
                    TvGamepadButton.y,
                    TvGamepadButton.l1,
                    TvGamepadButton.r1,
                    TvGamepadButton.start,
                    TvGamepadButton.select,
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TvGamepadGlyph(
                          button: button,
                          style: effectiveStyle,
                          size: 26,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          button == TvGamepadButton.a
                              ? '确认 / 激活'
                              : (tvActionLabels[_gamepadHint(button)] ?? '—'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        _SectionCard(
          title: '电视画面',
          children: <Widget>[
            _ScaleSlider(
              label: '界面缩放',
              value: settings.uiScale,
              min: 0.8,
              max: 1.3,
              divisions: 10,
              display: '${(settings.uiScale * 100).round()}%',
              hint: '10-foot UI 字号与控件整体比例，默认 100%。',
              onChanged: settings.setUiScale,
            ),
          ],
        ),
        _SectionCard(
          title: '遥控器',
          children: <Widget>[
            SwitchListTile(
              title: const Text('遥控器带媒体键'),
              subtitle: const Text(
                '关闭后不依赖全局媒体快捷键；方向键 + OK 仍可完成全部操作。',
              ),
              value: settings.remoteHasMediaKeys,
              onChanged: settings.setRemoteHasMediaKeys,
            ),
          ],
        ),
        _SectionCard(
          title: '按键学习 / 自定义映射',
          children: <Widget>[
            SwitchListTile(
              title: const Text('学习模式'),
              subtitle: const Text(
                '开启后按下的每个键都会被记录，期间不触发任何播放动作。用于兼容厂商私有键值。',
              ),
              value: settings.learningMode,
              onChanged: settings.setLearningMode,
            ),
            if (settings.learningMode)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '正在学习：请按需要绑定的按键，然后在下方为它选择动作，完成后关闭学习模式。',
                ),
              ),
            if (settings.learnedKeys.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无记录。按下一个未被识别的按键会自动出现在这里。'),
              )
            else
              for (final learned in settings.learnedKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 150,
                        child: Text(
                          TvKeyMaps.describe(learned.keyCode),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<TvAction>(
                          isExpanded: true,
                          value: settings.customBindings[learned.keyCode] ??
                              TvAction.none,
                          items: <DropdownMenuItem<TvAction>>[
                            for (final action in TvAction.values)
                              DropdownMenuItem<TvAction>(
                                value: action,
                                child: Text(
                                  tvActionLabels[action] ?? action.name,
                                ),
                              ),
                          ],
                          onChanged: (TvAction? value) {
                            if (value != null) {
                              settings.bindKey(learned.keyCode, value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: settings.clearLearnedKeys,
                    child: const Text('清空记录'),
                  ),
                  OutlinedButton(
                    onPressed: settings.resetBindings,
                    child: const Text('恢复默认映射'),
                  ),
                ],
              ),
            ),
          ],
        ),
        _SectionCard(
          title: '键位速查',
          children: <Widget>[
            _KeyMapTile(
              title: '遥控器（含媒体键）',
              bindings: TvKeyMaps.remote,
            ),
            _KeyMapTile(
              title: '手柄（Xbox / PlayStation 物理位置一致）',
              bindings: TvKeyMaps.gamepad,
            ),
            _KeyMapTile(title: '键盘', bindings: TvKeyMaps.keyboard),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  static TvAction _gamepadHint(TvGamepadButton button) {
    switch (button) {
      case TvGamepadButton.a:
        return TvAction.none;
      case TvGamepadButton.b:
        return TvAction.back;
      case TvGamepadButton.x:
        return TvAction.openPlayerPage;
      case TvGamepadButton.y:
        return TvAction.toggleMute;
      case TvGamepadButton.l1:
        return TvAction.previousTrack;
      case TvGamepadButton.r1:
        return TvAction.nextTrack;
      case TvGamepadButton.l2:
        return TvAction.seekBackward;
      case TvGamepadButton.r2:
        return TvAction.seekForward;
      case TvGamepadButton.start:
        return TvAction.playPause;
      case TvGamepadButton.select:
        return TvAction.openQueue;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final String hint;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label),
              const SizedBox(width: 8),
              Text(display),
            ],
          ),
          TvAdjustableSlider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value,
              label: display,
              onChanged: onChanged,
            ),
          ),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _KeyMapTile extends StatelessWidget {
  const _KeyMapTile({required this.title, required this.bindings});

  final String title;
  final Map<int, TvAction> bindings;

  @override
  Widget build(BuildContext context) {
    final entries = bindings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ExpansionTile(
      title: Text(title),
      children: <Widget>[
        for (final entry in entries)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 130,
              child: Text(
                TvKeyMaps.describe(entry.key),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            title: Text(tvActionLabels[entry.value] ?? entry.value.name),
          ),
      ],
    );
  }
}
