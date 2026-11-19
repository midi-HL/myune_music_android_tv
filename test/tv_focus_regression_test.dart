import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/tv/tv_focus_nav.dart';

Widget canvas(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox.expand(child: child)),
);

void main() {
  testWidgets('single-line input keeps horizontal editing and exits vertically', (tester) async {
    // Android IME handles caret arrows outside the widget test process. Use
    // desktop text shortcuts to assert that our shared input layer passes them.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final input = FocusNode();
    final below = FocusNode();
    final controller = TextEditingController();
    addTearDown(input.dispose);
    addTearDown(below.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(canvas(TvFocusScope(child: Stack(children: [
      Positioned(left: 100, top: 100, width: 200, child: TextField(
        focusNode: input, controller: controller,
      )),
      Positioned(left: 100, top: 250, child: Focus(
        focusNode: below, child: const SizedBox(width: 80, height: 40),
      )),
    ]))));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, 2);
    expect(input.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(below.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(input.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('focus bounds include scale and rotation', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(canvas(Align(
      alignment: Alignment.topLeft,
      child: Transform.scale(
        scale: 0.5,
        alignment: Alignment.topLeft,
        child: Focus(
          focusNode: node,
          child: const SizedBox(width: 100, height: 40),
        ),
      ),
    )));
    expect(TvFocusController.rectOf(node), const Rect.fromLTWH(0, 0, 50, 20));
    await tester.pumpWidget(canvas(Align(
      alignment: Alignment.topLeft,
      child: RotatedBox(
        quarterTurns: 1,
        child: Focus(
          focusNode: node,
          child: const SizedBox(width: 100, height: 40),
        ),
      ),
    )));
    final rotated = TvFocusController.rectOf(node)!;
    expect(rotated.width, closeTo(40, 0.000001));
    expect(rotated.height, closeTo(100, 0.000001));
  });

  testWidgets('outer hidden ancestors exclude nested visible focus', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(canvas(Offstage(
      offstage: true,
      child: Offstage(
        offstage: false,
        child: Focus(focusNode: node, child: const SizedBox(width: 40, height: 40)),
      ),
    )));
    expect(TvFocusController.rectOf(node), isNull);
    await tester.pumpWidget(canvas(Visibility(
      visible: false,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: Visibility(
        child: Focus(focusNode: node, child: const SizedBox(width: 40, height: 40)),
      ),
    )));
    expect(TvFocusController.rectOf(node), isNull);
  });

  testWidgets('focus restore and movement stay inside overlay layer', (tester) async {
    final background = FocusNode(debugLabel: 'background');
    final overlay = FocusNode(debugLabel: 'overlay');
    addTearDown(background.dispose);
    addTearDown(overlay.dispose);
    await tester.pumpWidget(canvas(Stack(children: [
      Positioned(left: 100, top: 200, child: Focus(
        focusNode: background, child: const SizedBox(width: 40, height: 40),
      )),
      Positioned(left: 100, top: 100, child: TvFocusLayer(child: Focus(
        focusNode: overlay, child: const SizedBox(width: 40, height: 40),
      ))),
    ])));
    background.requestFocus();
    await tester.pump();
    TvFocusController.instance.restoreFocusNow();
    await tester.pump();
    expect(overlay.hasPrimaryFocus, isTrue);
    expect(TvFocusController.instance.moveFocus(TraversalDirection.down, overlay), isFalse);
    await tester.pump();
    expect(overlay.hasPrimaryFocus, isTrue);
  });

  testWidgets('vertical slider changes value repeatedly and traps no other axis', (tester) async {
    var value = 50.0;
    await tester.pumpWidget(canvas(TvFocusScope(child: StatefulBuilder(
      builder: (context, setState) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 44, height: 130, child: TvAdjustableSlider(
          vertical: true,
          min: 0, max: 100, divisions: 100, value: value,
          onChanged: (next) => setState(() => value = next),
          child: RotatedBox(quarterTurns: -1, child: Slider(
            min: 0, max: 100, value: value,
            onChanged: (next) => setState(() => value = next),
          )),
        )),
      ),
    ))));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(value, 52);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(value, 51);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main content and bottom bar navigate both ways without horizontal drift', (tester) async {
    final content = FocusNode();
    final bottom = FocusNode();
    final neighbor = FocusNode();
    addTearDown(content.dispose);
    addTearDown(bottom.dispose);
    addTearDown(neighbor.dispose);
    await tester.pumpWidget(canvas(Stack(children: [
      Positioned(left: 300, top: 350, child: Focus(
        focusNode: content, child: const SizedBox(width: 40, height: 40),
      )),
      Positioned(left: 300, top: 560, child: Focus(
        focusNode: bottom, child: const SizedBox(width: 40, height: 40),
      )),
      Positioned(left: 240, top: 558, child: Focus(
        focusNode: neighbor, child: const SizedBox(width: 40, height: 40),
      )),
    ])));
    content.requestFocus();
    await tester.pump();
    expect(TvFocusController.instance.moveFocus(TraversalDirection.down, content, lockZone: true), isTrue);
    await tester.pump();
    expect(bottom.hasPrimaryFocus, isTrue);
    expect(TvFocusController.instance.moveFocus(TraversalDirection.up, bottom, lockZone: true), isTrue);
    await tester.pump();
    expect(content.hasPrimaryFocus, isTrue);
  });
}
