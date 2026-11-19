import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/tv/tv_app_info.dart';
import 'package:myune_music/widgets/ui_scale_scope.dart';

void main() {
  test('Android package and in-app release versions agree', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version: ([^+\s]+)\+(\d+)$', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), TvAppInfo.version);
    expect(int.parse(match.group(2)!), greaterThan(1));
  });

  Future<double> scaleFor(WidgetTester tester, Size size, double visual) async {
    late double result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: UiScaleScope(
          visualScale: visual,
          child: Builder(builder: (context) {
            result = playPageScale(context);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    return result;
  }

  testWidgets('Player scale compensates the enclosing Android transform',
      (tester) async {
    const size = Size(1150, 620);
    final baseline = await scaleFor(tester, size, 1);
    final scaled = await scaleFor(tester, size, 0.72);
    expect(baseline, 1);
    expect(scaled * 0.72, closeTo(baseline, 0.00001));
  });

  testWidgets('Larger screens retain the established player size limit',
      (tester) async {
    expect(await scaleFor(tester, const Size(1920, 1080), 1), 1);
    expect(await scaleFor(tester, const Size(3840, 2160), 1), 1);
  });
}
