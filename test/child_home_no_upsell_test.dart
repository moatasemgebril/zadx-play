import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Regression test for P0 store policy (Google Play Families / Apple Kids):
// no subscription promo on the child's screens. Plans are reached only from
// the parent area behind the PIN.

void main() {
  test('the child home screen has no subscription promo or link to plans', () {
    final src = File('lib/features/home/home_screen.dart').readAsStringSync();
    expect(src, isNot(contains('Routes.subscription')));
    expect(src, isNot(contains('promoBanner')));
    expect(src, isNot(contains('_PromoButton')));
  });

  test('the plans screen is still reachable from the PIN-protected parent area', () {
    final src = File('lib/features/parent/parent_screen.dart').readAsStringSync();
    expect(src, contains('ParentGate('));
    expect(src, contains('Routes.subscription'));
  });
}
