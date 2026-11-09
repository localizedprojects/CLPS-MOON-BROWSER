// The Explore guide points out the region switch (1.14.0 review): its step
// comes right after Mission settings, top to bottom.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/content/guides.dart';

void main() {
  test('the Explore guide has a region step right after the pill', () {
    final ids = [for (final st in guideSteps['explore']!) st.target];
    expect(ids.indexOf('region'), ids.indexOf('pill') + 1);
    final st = guideSteps['explore']!.firstWhere((s) => s.target == 'region');
    expect(st.title, 'South pole or whole Moon');
    expect(st.body, contains('Whole Moon ranks'));
  });
}
