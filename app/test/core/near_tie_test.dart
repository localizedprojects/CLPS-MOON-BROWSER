// nearTieAtTopText (1.14.0 review): under the Whole Moon list header, one
// computed sentence says when the top of the ranking is a near tie, with the
// count and the spread taken from the scores themselves.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/text_runs.dart';
import 'package:polar_horizon/core/wording.dart';

void main() {
  test('the run from the first site within 1 point of it, its spread rounded up to 0.1', () {
    expect(nearTieAtTopText([69.3, 69.1, 68.9, 68.35, 67.5, 31.0]),
        'The top 4 sites score within 1.0 points of each other (out of 100): a near tie, so small differences decide their order.');
    expect(nearTieAtTopText([82.3, 82.3, 82.25, 70]), contains('The top 3 sites score within 0.1 points'));
    expect(nearTieAtTopText([50, 49.7]), contains('The top 2 sites score within 0.3 points'), reason: '0.3 stays 0.3 (no float round-up)');
    expect(nearTieAtTopText([50, 49.66]), contains('within 0.4 points'), reason: 'rounded up, so the sentence stays true');
    expect(nearTieAtTopText([60, 60, 60]), contains('The top 3 sites score within 0.1 points'));
    expect(nearTieAtTopText([60, 60, 60], within: 0.5), contains('The top 3 sites'));
  });

  test('no sentence without a near tie at the top', () {
    expect(nearTieAtTopText(const []), isNull);
    expect(nearTieAtTopText([70]), isNull);
    expect(nearTieAtTopText([70, 68.9, 68.8]), isNull, reason: 'the second is 1.1 points behind');
    expect(nearTieAtTopText([70, 69.4], within: 0.5), isNull);
  });

  test('every number in it is a number run (Plex Mono in the UI)', () {
    final runs = numberRuns(nearTieAtTopText([69.3, 69.1, 68.9])!);
    expect([for (final r in runs) if (r.number) r.text], ['3', '0.4', '100']);
  });
}
