import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/network/tv_network_widgets.dart';

Widget launcher(Future<void> Function(BuildContext) open) => MaterialApp(
  home: Scaffold(body: Builder(builder: (context) => TextButton(
    onPressed: () => open(context), child: const Text('open'),
  ))),
);

void main() {
  testWidgets('alert actions support intrinsic sizing and remain operable', (tester) async {
    await tester.pumpWidget(launcher((context) => showTvAlert(context, 'fixture alert')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('fixture alert'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('fixture alert'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm actions fit a narrow viewport without losing the result', (tester) async {
    tester.view.physicalSize = const Size(480, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(launcher((context) async {
      result = await showTvConfirm(context, 'fixture confirmation');
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded network buttons keep long labels and values within their row', (tester) async {
    var activated = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 180, child: TvActionButton(
        label: 'a long network source name', value: 'a long directory value',
        icon: Icons.cloud, onPressed: () => activated = true,
      )),
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('a long network source name'));
    expect(activated, isTrue);
  });

  testWidgets('network source editor scrolls in a short viewport and cancels', (tester) async {
    tester.view.physicalSize = const Size(480, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var returned = false;
    await tester.pumpWidget(launcher((context) async {
      final result = await showTvSourceEditor(context: context);
      expect(result, isNull);
      returned = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(tester.takeException(), isNull);
  });
}
