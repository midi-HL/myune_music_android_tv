import 'package:flutter/material.dart';

import '../../lyrics/lyric_source.dart';

class LyricSourceOrderDialog extends StatefulWidget {
  // 当前顺序（歌词来源 id 列表）
  final List<String> order;

  const LyricSourceOrderDialog({super.key, required this.order});

  @override
  State<LyricSourceOrderDialog> createState() => _LyricSourceOrderDialogState();
}

class _LyricSourceOrderDialogState extends State<LyricSourceOrderDialog> {
  late List<String> _order = LyricSource.normalizeOrder(widget.order);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final moved = _order.removeAt(oldIndex);
      _order.insert(newIndex, moved);
    });
  }

  /// 遥控器 / 手柄 / 键盘用：把某一项上移或下移一格。
  /// 拖拽手柄只服务鼠标，纯按键设备上无法触发长按拖动，所以这里补两个
  /// 独立可聚焦、OK 即可触发的按钮，保证全链路十字键可达。
  void _move(int index, int delta) {
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _order.length) return;
    setState(() {
      final moved = _order.removeAt(index);
      _order.insert(target, moved);
    });
  }

  void _resetToDefault() {
    setState(() {
      _order = List<String>.from(LyricSource.defaultOrderIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('歌词来源优先级'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '拖动，或聚焦某一项后按上移 / 下移按钮调整顺序，越靠上越优先\n',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 12),
            // 用 Flexible 包住列表：窗口较矮时列表自身滚动，而不是撑破对话框
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) {
                  final source = LyricSource.fromId(_order[index]);
                  if (source == null) return const SizedBox.shrink();

                  return Padding(
                    key: ValueKey(source.id),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${index + 1}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.label,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    source.description,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 遥控器：两个独立可聚焦按钮，方向键可达、OK 生效。
                            IconButton(
                              tooltip: '上移',
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              color: index == 0
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.primary,
                              onPressed: index == 0
                                  ? null
                                  : () => _move(index, -1),
                            ),
                            IconButton(
                              tooltip: '下移',
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              color: index == _order.length - 1
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.primary,
                              onPressed: index == _order.length - 1
                                  ? null
                                  : () => _move(index, 1),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Icon(
                                  Icons.drag_indicator,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _resetToDefault, child: const Text('重置')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_order),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
