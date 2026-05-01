import 'dart:math' as math;

const _microsecondsPerMinute = 60000000;

class ReadingPacePlanner {
  const ReadingPacePlanner({
    this.windowWordCount = 24,
    this.minimumWordDuration = const Duration(milliseconds: 150),
    this.budgetPadding = 1.02,
    this.maximumWordDurationMultiplier = 2.6,
  });

  final int windowWordCount;
  final Duration minimumWordDuration;
  final double budgetPadding;
  final double maximumWordDurationMultiplier;

  int indexForElapsed({
    required List<String> words,
    required int startIndex,
    required double wordsPerMinute,
    required Duration elapsed,
  }) {
    if (words.isEmpty) {
      return 0;
    }

    final safeStart = startIndex.clamp(0, words.length - 1).toInt();
    var currentIndex = safeStart;
    var remainingMicros = elapsed.inMicroseconds;

    while (currentIndex < words.length - 1) {
      final durations = planWindowMicros(
        words: words,
        startIndex: currentIndex,
        wordsPerMinute: wordsPerMinute,
      );
      if (durations.isEmpty) {
        return currentIndex;
      }

      for (final durationMicros in durations) {
        if (currentIndex >= words.length - 1) {
          return currentIndex;
        }
        if (remainingMicros < durationMicros) {
          return currentIndex;
        }
        remainingMicros -= durationMicros;
        currentIndex += 1;
      }
    }

    return currentIndex;
  }

  List<Duration> planWindow({
    required List<String> words,
    required int startIndex,
    required double wordsPerMinute,
  }) {
    return planWindowMicros(
      words: words,
      startIndex: startIndex,
      wordsPerMinute: wordsPerMinute,
    ).map((micros) => Duration(microseconds: micros)).toList(growable: false);
  }

  List<int> planWindowMicros({
    required List<String> words,
    required int startIndex,
    required double wordsPerMinute,
  }) {
    if (words.isEmpty || wordsPerMinute <= 0 || windowWordCount <= 0) {
      return const [];
    }

    final safeStart = startIndex.clamp(0, words.length - 1).toInt();
    final endIndex = math.min(words.length, safeStart + windowWordCount);
    final count = endIndex - safeStart;
    if (count <= 0) {
      return const [];
    }

    final targetMicros = (_microsecondsPerMinute / wordsPerMinute)
        .round()
        .clamp(1, 1 << 31)
        .toInt();
    final minimumMicros = math.min(
      minimumWordDuration.inMicroseconds,
      targetMicros,
    );
    final budgetMicros = math
        .max(
          minimumMicros * count,
          (targetMicros * count * budgetPadding).round(),
        )
        .toDouble();
    final maximumMicros = math.max(
      minimumMicros.toDouble(),
      targetMicros * maximumWordDurationMultiplier,
    );
    final maxExtraMicros = maximumMicros - minimumMicros;
    final desiredExtras = <double>[];
    final stretchWeights = <double>[];

    for (var index = safeStart; index < endIndex; index += 1) {
      final profile = _WordPaceProfile.from(words[index]);
      desiredExtras.add(
        (profile.lengthBonusMicros + profile.punctuationBonusMicros)
            .clamp(0, maxExtraMicros)
            .toDouble(),
      );
      stretchWeights.add(profile.stretchWeight);
    }

    final extraBudgetMicros = budgetMicros - minimumMicros * count;
    final extras = _fitExtrasToBudget(
      desiredExtras: desiredExtras,
      stretchWeights: stretchWeights,
      extraBudgetMicros: extraBudgetMicros,
      maxExtraMicros: maxExtraMicros,
    );

    final durations = List<int>.generate(
      count,
      (index) => (minimumMicros + extras[index]).round(),
      growable: false,
    );
    _correctRounding(
      durations: durations,
      targetTotalMicros: budgetMicros.round(),
      minimumMicros: minimumMicros,
      maximumMicros: maximumMicros.round(),
    );
    return durations;
  }

  static List<double> _fitExtrasToBudget({
    required List<double> desiredExtras,
    required List<double> stretchWeights,
    required double extraBudgetMicros,
    required double maxExtraMicros,
  }) {
    if (desiredExtras.isEmpty ||
        extraBudgetMicros <= 0 ||
        maxExtraMicros <= 0) {
      return List<double>.filled(desiredExtras.length, 0);
    }

    final extras = desiredExtras
        .map((extra) => extra.clamp(0, maxExtraMicros).toDouble())
        .toList(growable: false);
    final desiredTotal = extras.fold<double>(0, (sum, extra) => sum + extra);

    if (desiredTotal > extraBudgetMicros) {
      final scale = extraBudgetMicros / desiredTotal;
      return extras.map((extra) => extra * scale).toList(growable: false);
    }

    var remaining = extraBudgetMicros - desiredTotal;
    remaining = _distributeExtra(
      extras: extras,
      weights: stretchWeights,
      amount: remaining,
      maxExtraMicros: maxExtraMicros,
    );
    if (remaining > 0.5) {
      remaining = _distributeExtra(
        extras: extras,
        weights: List<double>.filled(extras.length, 1),
        amount: remaining,
        maxExtraMicros: maxExtraMicros,
      );
    }
    return extras;
  }

  static double _distributeExtra({
    required List<double> extras,
    required List<double> weights,
    required double amount,
    required double maxExtraMicros,
  }) {
    var remaining = amount;
    while (remaining > 0.5) {
      final activeIndexes = <int>[];
      var weightTotal = 0.0;

      for (var index = 0; index < extras.length; index += 1) {
        final weight = weights[index];
        if (weight <= 0 || extras[index] >= maxExtraMicros) {
          continue;
        }
        activeIndexes.add(index);
        weightTotal += weight;
      }

      if (activeIndexes.isEmpty || weightTotal <= 0) {
        break;
      }

      var distributed = 0.0;
      for (final index in activeIndexes) {
        final share = remaining * weights[index] / weightTotal;
        final room = maxExtraMicros - extras[index];
        final addition = math.min(share, room);
        extras[index] += addition;
        distributed += addition;
      }

      if (distributed <= 0.5) {
        break;
      }
      remaining -= distributed;
    }

    return remaining;
  }

  static void _correctRounding({
    required List<int> durations,
    required int targetTotalMicros,
    required int minimumMicros,
    required int maximumMicros,
  }) {
    var difference =
        targetTotalMicros - durations.fold<int>(0, (sum, value) => sum + value);
    if (difference == 0) {
      return;
    }

    for (
      var index = durations.length - 1;
      index >= 0 && difference != 0;
      index -= 1
    ) {
      if (difference > 0) {
        final room = maximumMicros - durations[index];
        if (room <= 0) {
          continue;
        }
        final addition = math.min(room, difference);
        durations[index] += addition;
        difference -= addition;
      } else {
        final room = durations[index] - minimumMicros;
        if (room <= 0) {
          continue;
        }
        final subtraction = math.min(room, -difference);
        durations[index] -= subtraction;
        difference += subtraction;
      }
    }
  }
}

class _WordPaceProfile {
  const _WordPaceProfile({
    required this.lengthBonusMicros,
    required this.punctuationBonusMicros,
    required this.stretchWeight,
  });

  factory _WordPaceProfile.from(String word) {
    final coreLength = _coreLength(word);
    final lengthExcess = math.max(0, coreLength - _shortWordLength);
    final lengthBonus = math.min(
      _maxLengthBonusMicros,
      lengthExcess * _lengthStepMicros,
    );

    return _WordPaceProfile(
      lengthBonusMicros: lengthBonus,
      punctuationBonusMicros: _punctuationBonus(word),
      stretchWeight: lengthExcess.toDouble(),
    );
  }

  final int lengthBonusMicros;
  final int punctuationBonusMicros;
  final double stretchWeight;

  static const _shortWordLength = 4;
  static const _lengthStepMicros = 22000;
  static const _maxLengthBonusMicros = 220000;
  static const _commaPauseMicros = 20000;
  static const _clausePauseMicros = 35000;
  static const _sentencePauseMicros = 75000;
  static const _strongSentencePauseMicros = 95000;
  static const _ellipsisPauseMicros = 120000;
  static const _edgePunctuation = ' \t\n\r"\'`([{<)]}>.,;:!?';

  static int _coreLength(String word) {
    var start = 0;
    var end = word.length;

    while (start < end && _edgePunctuation.contains(word[start])) {
      start += 1;
    }
    while (end > start && _edgePunctuation.contains(word[end - 1])) {
      end -= 1;
    }

    return end - start;
  }

  static int _punctuationBonus(String word) {
    final value = word.trimRight();
    if (value.isEmpty) {
      return 0;
    }
    if (value.endsWith('...')) {
      return _ellipsisPauseMicros;
    }
    if (value.endsWith('!') || value.endsWith('?')) {
      return _strongSentencePauseMicros;
    }
    if (value.endsWith('.')) {
      return _sentencePauseMicros;
    }
    if (value.endsWith(';') || value.endsWith(':')) {
      return _clausePauseMicros;
    }
    if (value.endsWith(',')) {
      return _commaPauseMicros;
    }
    return 0;
  }
}
