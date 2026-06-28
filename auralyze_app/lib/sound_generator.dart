import 'dart:math' as math;

class GeneratedSound {
  GeneratedSound({
    required this.name,
    required this.description,
    required this.sampleRate,
    required this.samples,
    required this.layers,
  });

  final String name;
  final String description;
  final int sampleRate;
  final List<double> samples;
  final List<String> layers;
}

class PromptSoundGenerator {
  static const int sampleRate = 44100;

  GeneratedSound generate(String prompt) {
    final query = prompt.toLowerCase();
    if (_hasAny(query, ['laser', 'zap', 'blaster', 'cyber'])) {
      return _laser(prompt);
    }
    if (_hasAny(query, ['impact', 'explosion', 'boom', 'hit', 'cinematic'])) {
      return _impact(prompt);
    }
    if (_hasAny(query, ['rain', 'tokyo', 'night', 'ambience', 'ambient'])) {
      return _rain(prompt);
    }
    if (_hasAny(query, ['riser', 'build', 'uplift', 'sweep'])) {
      return _riser(prompt);
    }
    if (_hasAny(query, ['warm', 'analog', 'pad', 'drone', 'dark'])) {
      return _drone(prompt);
    }
    if (_hasAny(query, ['voice', 'vocal', 'robot', 'alien'])) {
      return _vocalTexture(prompt);
    }
    return _hybrid(prompt);
  }

  bool _hasAny(String query, List<String> terms) {
    return terms.any(query.contains);
  }

  GeneratedSound _laser(String prompt) {
    const seconds = 1.35;
    final samples = _render(seconds, (i, t) {
      final p = t / seconds;
      final freq = _lerp(2100, 120, math.pow(p, .62).toDouble());
      final env = math.exp(-5.8 * p);
      final wobble = math.sin(2 * math.pi * 34 * t) * 0.09;
      final tone = math.sin(2 * math.pi * freq * t + wobble);
      final bite = math.sin(2 * math.pi * freq * 1.98 * t) * .22;
      return (tone + bite) * env * .78;
    });
    return GeneratedSound(
      name: 'prompt_laser.wav',
      description: 'Falling pitch laser with FM bite and short tail.',
      sampleRate: sampleRate,
      samples: _limit(samples),
      layers: const ['pitch sweep oscillator', 'FM edge', 'short decay'],
    );
  }

  GeneratedSound _impact(String prompt) {
    const seconds = 2.4;
    final random = math.Random(prompt.hashCode);
    final samples = _render(seconds, (i, t) {
      final p = t / seconds;
      final thump =
          math.sin(2 * math.pi * (48 - 18 * p) * t) * math.exp(-7.5 * p);
      final body = math.sin(2 * math.pi * 92 * t) * math.exp(-4.1 * p) * .45;
      final crack =
          (random.nextDouble() * 2 - 1) * math.exp(-36 * p) * (p < .18 ? 1 : 0);
      final tail = (random.nextDouble() * 2 - 1) * math.exp(-2.7 * p) * .16;
      return thump * .9 + body + crack * .55 + tail;
    });
    return GeneratedSound(
      name: 'prompt_impact.wav',
      description:
          'Layered cinematic hit with sub thump, crack, and noisy room tail.',
      sampleRate: sampleRate,
      samples: _limit(samples),
      layers: const [
        'sub drop',
        'body resonance',
        'transient crack',
        'noise tail',
      ],
    );
  }

  GeneratedSound _rain(String prompt) {
    const seconds = 4.0;
    final random = math.Random(prompt.hashCode);
    var dripPhase = 0.0;
    final samples = _render(seconds, (i, t) {
      final p = t / seconds;
      final hiss = (random.nextDouble() * 2 - 1) * .16;
      final gust = math.sin(2 * math.pi * .13 * t) * .08;
      final dripTrigger = random.nextDouble() > .997 ? 1.0 : 0.0;
      dripPhase = dripTrigger > 0 ? 1.0 : math.max(0, dripPhase - .012);
      final drip = math.sin(2 * math.pi * 1300 * t) * dripPhase * .18;
      final distant = math.sin(2 * math.pi * 180 * t) * .04 * (1 - p * .15);
      return hiss + gust + drip + distant;
    });
    return GeneratedSound(
      name: 'prompt_rain_ambience.wav',
      description:
          'Noisy rain bed with random droplets and distant city low tone.',
      sampleRate: sampleRate,
      samples: _limit(_soften(samples, .72)),
      layers: const ['rain noise', 'random droplets', 'slow gust', 'city hum'],
    );
  }

  GeneratedSound _riser(String prompt) {
    const seconds = 3.2;
    final samples = _render(seconds, (i, t) {
      final p = t / seconds;
      final freq = _lerp(180, 4200, p * p);
      final env = math.sin(math.pi * p).clamp(0, 1).toDouble();
      final tone = math.sin(2 * math.pi * freq * t);
      final shimmer = math.sin(2 * math.pi * (freq * 1.51) * t) * .22;
      final tremolo = .72 + .28 * math.sin(2 * math.pi * _lerp(3, 18, p) * t);
      return (tone + shimmer) * env * tremolo * .62;
    });
    return GeneratedSound(
      name: 'prompt_riser.wav',
      description:
          'Rising synth sweep with increasing tremolo and harmonic shimmer.',
      sampleRate: sampleRate,
      samples: _limit(samples),
      layers: const ['pitch rise', 'harmonic shimmer', 'tempo tremolo'],
    );
  }

  GeneratedSound _drone(String prompt) {
    const seconds = 4.2;
    final samples = _render(seconds, (i, t) {
      final env = _fadeInOut(t, seconds, .35);
      final root = math.sin(2 * math.pi * 110 * t);
      final fifth = math.sin(2 * math.pi * 165 * t + .4) * .62;
      final octave = math.sin(2 * math.pi * 220 * t + .9) * .35;
      final motion = math.sin(2 * math.pi * .19 * t) * .18;
      final dust = math.sin(2 * math.pi * 880 * t) * .04;
      return (root + fifth + octave + dust) * env * (.42 + motion);
    });
    return GeneratedSound(
      name: 'prompt_warm_drone.wav',
      description: 'Warm analog-style drone with slow amplitude motion.',
      sampleRate: sampleRate,
      samples: _limit(_soften(samples, .84)),
      layers: const ['root oscillator', 'fifth', 'octave', 'tape dust'],
    );
  }

  GeneratedSound _vocalTexture(String prompt) {
    const seconds = 2.2;
    final samples = _render(seconds, (i, t) {
      final p = t / seconds;
      final formant = _lerp(520, 940, .5 + .5 * math.sin(2 * math.pi * .8 * t));
      final carrier = 130 + 18 * math.sin(2 * math.pi * 5.2 * t);
      final env = _fadeInOut(t, seconds, .12) * math.exp(-.35 * p);
      final buzz = math.sin(2 * math.pi * carrier * t);
      final mouth = math.sin(2 * math.pi * formant * t) * .45;
      final robot = math.sin(2 * math.pi * 38 * t) * buzz * .25;
      return (buzz * .5 + mouth + robot) * env * .55;
    });
    return GeneratedSound(
      name: 'prompt_vocal_texture.wav',
      description: 'Alien/robot vocal texture with formant motion.',
      sampleRate: sampleRate,
      samples: _limit(samples),
      layers: const ['buzz carrier', 'moving formant', 'ring modulation'],
    );
  }

  GeneratedSound _hybrid(String prompt) {
    const seconds = 2.8;
    final random = math.Random(prompt.hashCode);
    final samples = _render(seconds, (i, t) {
      final p = t / seconds;
      final tone =
          math.sin(2 * math.pi * _lerp(220, 96, p) * t) * math.exp(-2.6 * p);
      final texture = (random.nextDouble() * 2 - 1) * math.exp(-1.4 * p) * .14;
      final pulse = math.sin(2 * math.pi * 7 * t) > .55 ? .16 : 0.0;
      return tone * .55 + texture + pulse;
    });
    return GeneratedSound(
      name: 'prompt_custom_sound.wav',
      description:
          'Hybrid prompt sound with tonal body, texture, and pulse motion.',
      sampleRate: sampleRate,
      samples: _limit(samples),
      layers: const ['tone body', 'noise texture', 'pulse automation'],
    );
  }

  List<double> _render(double seconds, double Function(int i, double t) fn) {
    final count = (sampleRate * seconds).round();
    return List<double>.generate(count, (i) => fn(i, i / sampleRate));
  }

  List<double> _soften(List<double> input, double amount) {
    var previous = 0.0;
    return input.map((sample) {
      previous = previous * amount + sample * (1 - amount);
      return previous;
    }).toList();
  }

  List<double> _limit(List<double> input) {
    var peak = .001;
    for (final sample in input) {
      peak = math.max(peak, sample.abs());
    }
    final gain = .92 / peak;
    return input
        .map((sample) => _softClip(sample * gain * 1.15) * .88)
        .toList();
  }

  double _softClip(double value) {
    final limited = value.clamp(-8.0, 8.0).toDouble();
    final curve = math.exp(2 * limited);
    return (curve - 1) / (curve + 1);
  }

  double _fadeInOut(double t, double seconds, double fade) {
    final fadeIn = (t / fade).clamp(0, 1).toDouble();
    final fadeOut = ((seconds - t) / fade).clamp(0, 1).toDouble();
    return math.min(fadeIn, fadeOut);
  }

  double _lerp(num a, num b, num t) {
    return a.toDouble() + (b.toDouble() - a.toDouble()) * t.toDouble();
  }
}
