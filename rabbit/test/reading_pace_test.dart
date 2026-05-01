import 'package:flutter_test/flutter_test.dart';

import 'package:cinder_reading/src/reading_pace.dart';

void main() {
  test(
    'keeps short words at the minimum while preserving the window average',
    () {
      const planner = ReadingPacePlanner(windowWordCount: 5, budgetPadding: 1);

      final durations = planner.planWindow(
        words: const ['A', 'il', 'evidentemente', 'camminiamo', 'velocemente'],
        startIndex: 0,
        wordsPerMinute: 300,
      );

      expect(durations[0], const Duration(milliseconds: 150));
      expect(durations[1], const Duration(milliseconds: 150));
      expect(durations[2], greaterThan(durations[3]));
      expect(
        durations.fold<int>(
          0,
          (sum, duration) => sum + duration.inMicroseconds,
        ),
        const Duration(milliseconds: 1000).inMicroseconds,
      );
    },
  );

  test('adds punctuation pauses before redistributing spare budget', () {
    const planner = ReadingPacePlanner(windowWordCount: 4, budgetPadding: 1);

    final durations = planner.planWindow(
      words: const ['ciao,', 'il', 'mondo', 'continua'],
      startIndex: 0,
      wordsPerMinute: 300,
    );

    expect(durations[0], const Duration(milliseconds: 170));
    expect(durations[1], const Duration(milliseconds: 150));
    expect(
      durations[3].inMilliseconds,
      greaterThan(durations[2].inMilliseconds),
    );
    expect(
      durations.fold<int>(0, (sum, duration) => sum + duration.inMicroseconds),
      const Duration(milliseconds: 800).inMicroseconds,
    );
  });

  test('resolves elapsed playback using the planned word durations', () {
    const planner = ReadingPacePlanner(windowWordCount: 4, budgetPadding: 1);
    const words = ['ciao,', 'il', 'mondo', 'continua'];

    expect(
      planner.indexForElapsed(
        words: words,
        startIndex: 0,
        wordsPerMinute: 300,
        elapsed: const Duration(milliseconds: 169),
      ),
      0,
    );
    expect(
      planner.indexForElapsed(
        words: words,
        startIndex: 0,
        wordsPerMinute: 300,
        elapsed: const Duration(milliseconds: 170),
      ),
      1,
    );
  });
}
