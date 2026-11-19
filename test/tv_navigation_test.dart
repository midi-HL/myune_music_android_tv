import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:myune_music/layout/navigation_notifier.dart';
import 'package:myune_music/tv/tv_focus_nav.dart';
import 'package:myune_music/tv/tv_navigation.dart';

Future<void> back(WidgetTester tester) async {
  // The production handler deliberately coalesces duplicate native / Flutter Back events.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
  await TvBackHandler.handle();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Back closes popup in nested Navigator instead of exiting app', (tester) async {
    final navigation = NavigationNotifier();
    addTearDown(navigation.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: navigation,
      child: MaterialApp(
        navigatorKey: tvRootNavigatorKey,
        navigatorObservers: [TvFocusNavigatorObserver()],
        home: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('inner page')),
        )),
      ),
    ));
    final menu = showMenu<String>(
      context: tester.element(find.text('inner page')),
      position: const RelativeRect.fromLTRB(20, 20, 100, 100),
      items: const [PopupMenuItem(value: 'item', child: Text('song action'))],
    );
    await tester.pumpAndSettle();
    await back(tester);
    await menu;
    expect(find.text('song action'), findsNothing);
    expect(find.text('inner page'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Back closes dialog above drawer before closing the drawer', (tester) async {
    final navigation = NavigationNotifier();
    addTearDown(navigation.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: navigation,
      child: MaterialApp(
        navigatorKey: tvRootNavigatorKey,
        navigatorObservers: [TvFocusNavigatorObserver()],
        home: Scaffold(
          key: tvScaffoldKey,
          endDrawer: const Drawer(child: TextButton(onPressed: null, child: Text('queue'))),
          body: const Text('home'),
        ),
      ),
    ));
    tvScaffoldKey.currentState!.openEndDrawer();
    await tester.pumpAndSettle();
    final dialog = showDialog<void>(
      context: tvScaffoldKey.currentContext!,
      builder: (_) => const AlertDialog(title: Text('save queue')),
    );
    await tester.pumpAndSettle();
    await back(tester);
    await dialog;
    expect(find.text('save queue'), findsNothing);
    expect(tvScaffoldKey.currentState!.isEndDrawerOpen, isTrue);
    await back(tester);
    expect(tvScaffoldKey.currentState!.isEndDrawerOpen, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active page gets Back and stale callback cannot remove replacement', (tester) async {
    final navigation = NavigationNotifier();
    addTearDown(navigation.dispose);
    var calls = 0;
    var exits = 0;
    bool stale() => false;
    bool active() { calls++; return true; }
    TvBackHandler.registerPageHandler('/playlist', stale);
    TvBackHandler.registerPageHandler('/playlist', active);
    TvBackHandler.unregisterPageHandler('/playlist', stale);
    addTearDown(() => TvBackHandler.unregisterPageHandler('/playlist', active));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: navigation,
      child: MaterialApp(
        navigatorKey: tvRootNavigatorKey,
        navigatorObservers: [TvFocusNavigatorObserver()],
        home: const Scaffold(body: Text('network content')),
      ),
    ));
    await back(tester);
    expect(calls, 1);
    expect(exits, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
