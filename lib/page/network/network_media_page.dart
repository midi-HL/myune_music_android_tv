import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Text(
                '网络媒体',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 190,
                child: TvActionButton(
                  label: '网络硬盘 / 网盘',
                  icon: Icons.cloud_outlined,
                  selected: _tab == 0,
                  autofocus: true,
                  onPressed: () => setState(() => _tab = 0),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: TvActionButton(
                  label: '哔哩哔哩',
                  icon: Icons.smart_display_outlined,
                  selected: _tab == 1,
                  onPressed: () => setState(() => _tab = 1),
                ),
              ),
              const Spacer(),
              Text(
                '方向键移动 · OK 确认 · 返回键退出输入',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const <Widget>[
              NetworkSourcesView(),
              BilibiliView(),
            ],
          ),
        ),
      ],
    );
  }
}
