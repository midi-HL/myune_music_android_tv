import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myune_music/layout/app_shell.dart';
import 'package:myune_music/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Application starts with its native services and providers',
      (tester) async {
    await app.main();
    // Player backgrounds can animate continuously; use a bounded wait.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AppShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
