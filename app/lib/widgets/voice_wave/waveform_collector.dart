/// Collects mic amplitudes while recording and always reduces to [barCount] bars.
///
/// Live UI uses a scrolling window ([liveScrollUnits]); the full take is
/// bucketed into exactly [barCount] bars via [toBars] when sending.
class WaveformCollector {
  WaveformCollector({
    this.barCount = 32,
    this.liveWindow = 56,
  });

  final int barCount;
  /// How many recent samples are visible in the scrolling live preview.
  final int liveWindow;
  final List<double> _samples = [];
  final List<double> _live = [];

  int get sampleCount => _samples.length;

  void reset() {
    _samples.clear();
    _live.clear();
  }

  /// [db] is dBFS from the recorder (typically ~-160…0).
  void addDb(double db) {
    final unit = _dbToUnit(db);
    _samples.add(unit);
    _live.add(unit);
    if (_live.length > liveWindow) {
      _live.removeRange(0, _live.length - liveWindow);
    }
  }

  static double _dbToUnit(double db) {
    // Speech/voice useful range; silence floors low, peaks near 0 dBFS.
    const minDb = -50.0;
    const maxDb = -2.0;
    if (db <= minDb) return 0.08;
    if (db >= maxDb) return 1.0;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.08, 1.0);
  }

  /// Exactly [barCount] ints in 1…20 (peak per bucket) — for the saved message.
  List<int> toBars() {
    if (_samples.isEmpty) {
      return List<int>.filled(barCount, 3);
    }
    final out = List<int>.filled(barCount, 1);
    final n = _samples.length;
    for (var i = 0; i < barCount; i++) {
      final start = (i * n / barCount).floor();
      var end = ((i + 1) * n / barCount).ceil();
      if (end <= start) end = start + 1;
      if (end > n) end = n;
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        final v = _samples[j];
        if (v > peak) peak = v;
      }
      out[i] = (1 + (peak * 19).round()).clamp(1, 20);
    }
    return out;
  }

  /// Newest on the right; oldest slides off the left.
  List<double> liveScrollUnits() => List<double>.from(_live);
}
