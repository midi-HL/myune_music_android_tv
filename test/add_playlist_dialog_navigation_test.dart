import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_content_notifier.dart';
import 'package:myune_music/page/playlist/playlist_content_widget.dart';
import 'package:myune_music/tv/tv_focus_nav.dart';

class _PlaylistForDialog extends ChangeNotifier implements PlaylistContentNotifier {
  @override
  void setDisableHotKeys(bool value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('TV arrows move through add-playlist choices without changing mode', (tester) async {
    final notifier = _PlaylistForDialog();
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      builder: (_, child) => TvFocusScope(child: child!),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context, builder: (_) => AddPlaylistDialog(notifier: notifier),
        ),
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final field = find.byType(EditableText);
    final editable = tester.widget<EditableText>(field);
    await tester.enterText(find.byType(TextField), 'abc');
    expect(editable.focusNode.hasFocus, isTrue);
    expect(find.byType(RadioGroup<ManagementMode>), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editable.focusNode.hasFocus, isFalse);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'abc');
    expect(find.byType(RadioGroup<ManagementMode>), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final folderRow = find.widgetWithText(ListTile, '使用文件夹管理歌单');
    expect(find.descendant(of: folderRow, matching: find.byIcon(Icons.radio_button_unchecked)), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.descendant(of: folderRow, matching: find.byIcon(Icons.radio_button_checked)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
