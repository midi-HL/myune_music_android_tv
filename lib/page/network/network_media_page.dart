import 'package:flutter/material.dart';

import '../../tv/tv_focus_nav.dart';
import 'bilibili_view.dart';
import 'network_sources_view.dart';
import 'tv_network_widgets.dart';

/// 「网络媒体」主页面：一个导航入口下用两个遥控器可达的标签切换
/// 「网络硬盘 / 共享网盘」与「哔哩哔哩」，避免侧边栏项过多影响 TV 焦点布局。
class NetworkMediaPage extends StatefulWidget {
  const NetworkMediaPage({super.key});

  @override
  State<NetworkMediaPage> createState() => _NetworkMediaPageState();
}

class _NetworkMediaPageState extends State<NetworkMediaPage> {
  int _tab = 0;

  void _switchTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    // 切换后按「页面类型」把焦点重新落到目标页视觉上最靠前的控件。
    // 不用固定 FocusNode：网盘页在「源列表 / 文件浏览」两态间切换时，
    // 同一个节点会被两个互斥控件先后 attach，存在重复挂载风险。
    // 这里由 TvFocusController 等两帧、按视觉位置选当前页第一个叶子控件，
    // 自然落到 网盘「添加网络源」/「上一步」 或 B 站「搜索」。
    TvFocusController.instance.scheduleFocusWhere((context) {
      return tab == 0
          ? context.findAncestorWidgetOfExactType<NetworkSourcesView>() != null
          : context.findAncestorWidgetOfExactType<BilibiliView>() != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: <Widget>[
              Text(
                '网络媒体',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 190,
                child: TvActionButton(
                  label: '网络硬盘 / 网盘',
                  icon: Icons.cloud_outlined,
                  selected: _tab == 0,
                  autofocus: true,
                  onPressed: () => _switchTab(0),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: TvActionButton(
                  label: '哔哩哔哩',
                  icon: Icons.smart_display_outlined,
                  selected: _tab == 1,
                  onPressed: () => _switchTab(1),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // IndexedStack 会把两个子页都留在 widget / 焦点树里，离屏页的
          // RenderBox 与可见页坐标完全重叠。用 ExcludeFocus 让非激活页整棵
          // 退出焦点链，几何导航才不会把它当成候选（否则方向键会跨页乱跳）。
          child: IndexedStack(
            index: _tab,
            children: <Widget>[
              ExcludeFocus(
                excluding: _tab != 0,
                child: const NetworkSourcesView(),
              ),
              ExcludeFocus(
                excluding: _tab != 1,
                child: const BilibiliView(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
