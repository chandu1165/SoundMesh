import 'dart:math' as math;

class AuralyzeAnalyzer {
  AnalysisReport analyzeFiles({
    required List<ImportedAudio> files,
    required String releaseTarget,
  }) {
    if (files.isEmpty) {
      return analyzeDemo(releaseTarget: releaseTarget);
    }
    final stems = files.map(_stemFromImported).toList();
    final mix = _mix(stems);
    final metrics = analyzeMetrics(mix.samples, mix.sampleRate);
    final spectrum = analyzeSpectrum(mix.samples, mix.sampleRate);
    final enhancedSamples = renderEnhancedPreview(
      mix.samples,
      mix.sampleRate,
      metrics,
      spectrum,
      releaseTarget,
    );
    final markers = analyzeTimeline(mix.samples, mix.sampleRate);
    final conflicts = analyzeConflicts(stems);
    final issues = [
      ...diagnoseMix(metrics, spectrum),
      ...conflicts.map(
        (conflict) => AnalysisIssue(
          severity: conflict.severity,
          title: conflict.title,
          evidence: conflict.evidence,
          fix: conflict.fix,
        ),
      ),
    ];
    return AnalysisReport(
      fileName: files.length == 1
          ? files.first.name
          : '${files.length} imported stems',
      releaseTarget: releaseTarget,
      metrics: metrics,
      spectrum: spectrum,
      timelineMarkers: markers,
      stems: stems,
      conflicts: conflicts,
      issues: issues,
      fixes: buildFixes(metrics, spectrum, releaseTarget),
      plugins: buildPlugins(issues, releaseTarget),
      waveform: downsample(mix.samples, 180),
      mixSamples: mix.samples,
      enhancedSamples: enhancedSamples,
      sampleRate: mix.sampleRate,
    );
  }

  AnalysisReport analyzeDemo({String releaseTarget = 'Streaming'}) {
    const sampleRate = 44100;
    final stems = [
      _demoStem('lead_vocal.wav', 'vocal', sampleRate, [260, 3200], .45),
      _demoStem('guitar_bus.wav', 'guitar', sampleRate, [250, 3000], .50),
      _demoStem('kick.wav', 'kick', sampleRate, [55, 80], .65),
      _demoStem('bass_808.wav', 'bass', sampleRate, [55, 95], .55),
    ];
    final mix = _mix(stems);
    final metrics = analyzeMetrics(mix.samples, mix.sampleRate);
    final spectrum = analyzeSpectrum(mix.samples, mix.sampleRate);
    final enhancedSamples = renderEnhancedPreview(
      mix.samples,
      mix.sampleRate,
      metrics,
      spectrum,
      releaseTarget,
    );
    final markers = analyzeTimeline(mix.samples, mix.sampleRate);
    final conflicts = analyzeConflicts(stems);
    final issues = [
      ...diagnoseMix(metrics, spectrum),
      ...conflicts.map(
        (conflict) => AnalysisIssue(
          severity: conflict.severity,
          title: conflict.title,
          evidence: conflict.evidence,
          fix: conflict.fix,
        ),
      ),
    ];
    final fixes = buildFixes(metrics, spectrum, releaseTarget);
    final plugins = buildPlugins(issues, releaseTarget);
    return AnalysisReport(
      fileName: '${stems.length} demo stems',
      releaseTarget: releaseTarget,
      metrics: metrics,
      spectrum: spectrum,
      timelineMarkers: markers,
      stems: stems,
      conflicts: conflicts,
      issues: issues,
      fixes: fixes,
      plugins: plugins,
      waveform: downsample(mix.samples, 180),
      mixSamples: mix.samples,
      enhancedSamples: enhancedSamples,
      sampleRate: mix.sampleRate,
    );
  }

  AudioStem _demoStem(
    String name,
    String role,
    int sampleRate,
    List<double> frequencies,
    double gain,
  ) {
    final length = sampleRate * 3;
    final samples = List<double>.filled(length, 0);
    for (var i = 0; i < length; i += 1) {
      final t = i / sampleRate;
      var value = 0.0;
      for (final frequency in frequencies) {
        value += math.sin(2 * math.pi * frequency * t);
      }
      final envelope = role == 'kick'
          ? (i % (sampleRate ~/ 2) < 1600 ? 1.0 : 0.05)
          : 0.78 + .22 * math.sin(2 * math.pi * .7 * t);
      samples[i] = value * gain * envelope / frequencies.length;
    }
    final metrics = analyzeMetrics(samples, sampleRate);
    final spectrum = analyzeSpectrum(samples, sampleRate);
    return AudioStem(
      name: name,
      role: role,
      samples: samples,
      sampleRate: sampleRate,
      metrics: metrics,
      spectrum: spectrum,
    );
  }

  AudioStem _stemFromImported(ImportedAudio audio) {
    final metrics = analyzeMetrics(audio.samples, audio.sampleRate);
    final spectrum = analyzeSpectrum(audio.samples, audio.sampleRate);
    return AudioStem(
      name: audio.name,
      role: inferRole(audio.name, spectrum),
      samples: audio.samples,
      sampleRate: audio.sampleRate,
      metrics: metrics,
      spectrum: spectrum,
    );
  }

  AudioStem _mix(List<AudioStem> stems) {
    final length = stems.map((stem) => stem.samples.length).reduce(math.min);
    final sampleRate = stems.first.sampleRate;
    final gain = 1 / math.max(2, math.sqrt(stems.length));
    final samples = List<double>.filled(length, 0);
    for (final stem in stems) {
      for (var i = 0; i < length; i += 1) {
        samples[i] += stem.samples[i] * gain;
      }
    }
    final metrics = analyzeMetrics(samples, sampleRate);
    final spectrum = analyzeSpectrum(samples, sampleRate);
    return AudioStem(
      name: 'mix',
      role: 'mix',
      samples: samples,
      sampleRate: sampleRate,
      metrics: metrics,
      spectrum: spectrum,
    );
  }

  String inferRole(String name, SpectrumProfile spectrum) {
    final lower = name.toLowerCase();
    if (RegExp('vox|vocal|voice|lead|rap|dialog|dialogue').hasMatch(lower)) {
      return 'vocal';
    }
    if (RegExp('kick|bd|bass drum').hasMatch(lower)) return 'kick';
    if (RegExp('bass|808|sub').hasMatch(lower)) return 'bass';
    if (RegExp('drum|perc|snare|hat|cymbal|beat').hasMatch(lower)) {
      return 'drums';
    }
    if (RegExp('guitar|gtr|riff').hasMatch(lower)) return 'guitar';
    if (RegExp('piano|keys|synth|pad|organ').hasMatch(lower)) return 'keys';
    final low = (spectrum.bands['sub'] ?? 0) + (spectrum.bands['bass'] ?? 0);
    final presence = spectrum.bands['presence'] ?? 0;
    if (low > .34) return 'bass';
    if (presence > .24) return 'vocal';
    return 'music';
  }

  AnalysisMetrics analyzeMetrics(List<double> samples, int sampleRate) {
    var peak = 0.0;
    var sumSquares = 0.0;
    var clipped = 0;
    final frameRms = <double>[];
    final frameSize = math.max(1024, (sampleRate * .25).floor());
    var frameSum = 0.0;
    var frameSamples = 0;

    for (final sample in samples) {
      final abs = sample.abs();
      peak = math.max(peak, abs);
      sumSquares += sample * sample;
      if (abs > .995) {
        clipped += 1;
      }
      frameSum += sample * sample;
      frameSamples += 1;
      if (frameSamples >= frameSize) {
        frameRms.add(math.sqrt(frameSum / frameSamples));
        frameSum = 0;
        frameSamples = 0;
      }
    }
    if (frameSamples > 0) {
      frameRms.add(math.sqrt(frameSum / frameSamples));
    }

    final rms = math.sqrt(sumSquares / samples.length);
    final peakDb = _db(peak);
    final loudnessDb = _db(rms);
    final sortedFrames = frameRms.map(_db).toList()..sort();
    final noiseFloor =
        sortedFrames[(sortedFrames.length * .1).floor().clamp(
          0,
          sortedFrames.length - 1,
        )];
    return AnalysisMetrics(
      peakDb: peakDb,
      truePeakDb: estimateTruePeak(samples),
      loudnessDb: loudnessDb,
      lufsApprox: loudnessDb - .7,
      noiseFloorDb: noiseFloor,
      crestFactor: peakDb - loudnessDb,
      clippedRatio: clipped / samples.length,
    );
  }

  double estimateTruePeak(List<double> samples) {
    var peak = 0.0;
    for (var i = 1; i < samples.length; i += 1) {
      final previous = samples[i - 1];
      final current = samples[i];
      peak = math.max(
        peak,
        math.max(
          previous.abs(),
          math.max(((previous + current) / 2).abs(), current.abs()),
        ),
      );
    }
    return _db(peak);
  }

  SpectrumProfile analyzeSpectrum(List<double> samples, int sampleRate) {
    const fftSize = 2048;
    final frameCount = math.min(24, math.max(4, samples.length ~/ fftSize));
    final hop = math.max(1, (samples.length - fftSize) ~/ frameCount);
    final bands = {
      'sub': 0.0,
      'bass': 0.0,
      'lowMid': 0.0,
      'mid': 0.0,
      'presence': 0.0,
      'harsh': 0.0,
      'air': 0.0,
    };
    final visual = List<double>.filled(64, 0);
    var total = 0.0;

    for (var frame = 0; frame < frameCount; frame += 1) {
      final start = math.min(samples.length - fftSize, frame * hop);
      final real = List<double>.filled(fftSize, 0);
      final imag = List<double>.filled(fftSize, 0);
      for (var i = 0; i < fftSize; i += 1) {
        final window = .5 - .5 * math.cos(2 * math.pi * i / (fftSize - 1));
        real[i] = samples[start + i] * window;
      }
      _fft(real, imag);
      for (var bin = 1; bin < fftSize ~/ 2; bin += 1) {
        final frequency = bin * sampleRate / fftSize;
        final magnitude = real[bin] * real[bin] + imag[bin] * imag[bin];
        total += magnitude;
        final key = _bandFor(frequency);
        if (key != null) {
          bands[key] = bands[key]! + magnitude;
        }
        final visualIndex = (frequency / 16000 * visual.length).floor().clamp(
          0,
          visual.length - 1,
        );
        visual[visualIndex] += magnitude;
      }
    }

    if (total > 0) {
      for (final key in bands.keys) {
        bands[key] = bands[key]! / total;
      }
    }
    final maxVisual = visual.reduce(math.max);
    final normalizedVisual = maxVisual <= 0
        ? visual
        : visual.map((value) => math.sqrt(value / maxVisual)).toList();
    return SpectrumProfile(bands: bands, visualSpectrum: normalizedVisual);
  }

  List<TimelineFinding> analyzeTimeline(List<double> samples, int sampleRate) {
    final windowSize = math.max(2048, (sampleRate * 1.2).floor());
    final hop = math.max(1024, windowSize ~/ 2);
    final windows = <_Window>[];
    for (var start = 0; start < samples.length; start += hop) {
      final end = math.min(samples.length, start + windowSize);
      var sumSquares = 0.0;
      var peak = 0.0;
      var crossings = 0;
      var previous = samples[start];
      for (var i = start; i < end; i += 1) {
        final value = samples[i];
        peak = math.max(peak, value.abs());
        sumSquares += value * value;
        if ((value >= 0 && previous < 0) || (value < 0 && previous >= 0)) {
          crossings += 1;
        }
        previous = value;
      }
      final size = math.max(1, end - start);
      windows.add(
        _Window(
          start / sampleRate,
          _db(math.sqrt(sumSquares / size)),
          _db(peak),
          crossings / size,
        ),
      );
      if (end == samples.length) {
        break;
      }
    }
    final averageRms =
        windows.map((window) => window.rmsDb).reduce((a, b) => a + b) /
        windows.length;
    final markers = <TimelineFinding>[];
    for (final window in windows) {
      if (window.peakDb > -.15) {
        markers.add(
          TimelineFinding(
            AnalysisSeverity.critical,
            window.startSec,
            'Clipping risk',
            'Peak reaches ${window.peakDb.toStringAsFixed(1)} dBFS in this window.',
          ),
        );
      } else if (window.rmsDb > averageRms + 5) {
        markers.add(
          TimelineFinding(
            AnalysisSeverity.warning,
            window.startSec,
            'Loudness jump',
            'This section is ${(window.rmsDb - averageRms).toStringAsFixed(1)} dB above the window average.',
          ),
        );
      } else if (window.zeroCrossingRate > .13) {
        markers.add(
          TimelineFinding(
            AnalysisSeverity.warning,
            window.startSec,
            'Harsh texture risk',
            'Fast waveform changes suggest bright or noisy content.',
          ),
        );
      }
    }
    return markers.take(8).toList();
  }

  List<StemConflict> analyzeConflicts(List<AudioStem> stems) {
    final conflicts = <StemConflict>[];
    final vocal = stems.where((stem) => stem.role == 'vocal').firstOrNull;
    final kick = stems.where((stem) => stem.role == 'kick').firstOrNull;
    final bass = stems.where((stem) => stem.role == 'bass').firstOrNull;
    if (vocal != null) {
      for (final stem in stems.where(
        (stem) =>
            stem.role == 'guitar' ||
            stem.role == 'keys' ||
            stem.role == 'music',
      )) {
        final overlap = _overlap(vocal, stem, ['mid', 'presence']);
        if (overlap > .16) {
          conflicts.add(
            StemConflict(
              AnalysisSeverity.warning,
              'Vocal masked by ${stem.role}',
              'Shared mid/presence score ${(overlap * 100).round()}; ${stem.role} is close to vocal level.',
              'Dip ${stem.role} around 2-4 kHz when vocals are active.',
            ),
          );
        }
      }
    }
    if (kick != null && bass != null) {
      final overlap = _overlap(kick, bass, ['sub', 'bass']);
      if (overlap > .16) {
        conflicts.add(
          StemConflict(
            AnalysisSeverity.critical,
            'Kick and bass low-end collision',
            'Shared sub/bass score ${(overlap * 100).round()}.',
            'Choose one owner for 50-80 Hz and sidechain bass lightly from kick.',
          ),
        );
      }
    }
    return conflicts;
  }

  List<AnalysisIssue> diagnoseMix(
    AnalysisMetrics metrics,
    SpectrumProfile spectrum,
  ) {
    final issues = <AnalysisIssue>[];
    final lowMid = spectrum.bands['lowMid'] ?? 0;
    final presence = spectrum.bands['presence'] ?? 0;
    final harsh = spectrum.bands['harsh'] ?? 0;
    if (metrics.truePeakDb > -.2) {
      issues.add(
        AnalysisIssue(
          severity: AnalysisSeverity.warning,
          title: 'Peak headroom is almost gone',
          evidence:
              'True peak is ${metrics.truePeakDb.toStringAsFixed(1)} dBTP.',
          fix: 'Trim the mix before EQ, compression, or limiting.',
        ),
      );
    }
    if (lowMid > .18 && presence < .22) {
      issues.add(
        AnalysisIssue(
          severity: AnalysisSeverity.warning,
          title: 'Likely low-mid muddiness',
          evidence:
              'Low-mid energy is ${(lowMid * 100).round()}% while presence is ${(presence * 100).round()}%.',
          fix: 'Try a broad 1-3 dB cut around 220-320 Hz.',
        ),
      );
    }
    if (harsh > .12) {
      issues.add(
        AnalysisIssue(
          severity: AnalysisSeverity.warning,
          title: 'Harshness risk',
          evidence: '5-8 kHz energy is ${(harsh * 100).round()}%.',
          fix: 'Use dynamic EQ around 5-7 kHz and restore air only if needed.',
        ),
      );
    }
    return issues;
  }

  List<ProcessingStep> buildFixes(
    AnalysisMetrics metrics,
    SpectrumProfile spectrum,
    String target,
  ) {
    return [
      ProcessingStep(
        'Input trim',
        metrics.truePeakDb > -1
            ? 'Reduce input by 2 dB for safer headroom.'
            : 'Keep input gain unchanged.',
      ),
      ProcessingStep(
        'Sub cleanup',
        'High-pass below 35 Hz to remove inaudible rumble.',
      ),
      ProcessingStep(
        'Mud control',
        'Adaptive broad low-mid cut around 280 Hz when buildup is detected.',
      ),
      ProcessingStep(
        'Clarity lift',
        'Presence lift around 3.2 kHz plus harshness control around 6.5 kHz.',
      ),
      ProcessingStep(
        'Dynamics',
        'Bus compression with soft saturation and true-peak limiting.',
      ),
      ProcessingStep(
        'Release target',
        '$target translation target with codec-safe headroom.',
      ),
    ];
  }

  List<PluginRecommendation> buildPlugins(
    List<AnalysisIssue> issues,
    String target,
  ) {
    return [
      PluginRecommendation(
        'EQ',
        'Dynamic EQ',
        'Control mud, harshness, and reference gaps.',
      ),
      PluginRecommendation(
        'Dynamics',
        'Compressor',
        'Stabilize vocals and uneven sections.',
      ),
      PluginRecommendation(
        'Mastering',
        'True-peak limiter',
        'Protect output from codec overs.',
      ),
      PluginRecommendation(
        'Low end',
        'Sidechain EQ',
        'Let kick and bass share space.',
      ),
    ];
  }

  List<MasteringExport> buildMasteringExports(AnalysisReport report) {
    return [
      MasteringExport(
        'Spotify',
        '-14 LUFS',
        '-1.0 dBTP',
        'Balanced loudness with codec-safe true peak.',
      ),
      MasteringExport(
        'YouTube',
        '-14 LUFS',
        '-1.0 dBTP',
        'Clear midrange and restrained limiter pressure.',
      ),
      MasteringExport(
        'Club',
        '-9 LUFS',
        '-0.3 dBTP',
        'Higher density, stronger low-end control, louder transient impact.',
      ),
      MasteringExport(
        'Podcast',
        '-16 LUFS',
        '-1.5 dBTP',
        'Speech-first loudness with noise-floor and plosive control.',
      ),
      MasteringExport(
        'Cinema',
        '-23 LUFS',
        '-2.0 dBTP',
        'Wide dynamics and safer headroom for theatrical playback.',
      ),
    ];
  }

  ReferenceComparison compareWithReference({
    required AnalysisReport report,
    required ImportedAudio reference,
  }) {
    final referenceMetrics = analyzeMetrics(
      reference.samples,
      reference.sampleRate,
    );
    final referenceSpectrum = analyzeSpectrum(
      reference.samples,
      reference.sampleRate,
    );
    final findings = <ReferenceFinding>[];
    final loudnessDelta =
        report.metrics.lufsApprox - referenceMetrics.lufsApprox;
    final crestDelta =
        report.metrics.crestFactor - referenceMetrics.crestFactor;
    final truePeakDelta =
        report.metrics.truePeakDb - referenceMetrics.truePeakDb;

    if (loudnessDelta.abs() > 1.5) {
      findings.add(
        ReferenceFinding(
          severity: loudnessDelta < 0
              ? AnalysisSeverity.warning
              : AnalysisSeverity.critical,
          title: loudnessDelta < 0
              ? 'Mix is quieter than reference'
              : 'Mix is louder than reference',
          detail:
              'Integrated level is ${loudnessDelta.abs().toStringAsFixed(1)} LUFS ${loudnessDelta < 0 ? 'below' : 'above'} ${reference.name}.',
          action: loudnessDelta < 0
              ? 'Raise limiter input carefully or add gentle bus density before the limiter.'
              : 'Back off limiter input and preserve transient headroom.',
          delta: loudnessDelta,
        ),
      );
    }

    if (crestDelta.abs() > 2.0) {
      findings.add(
        ReferenceFinding(
          severity: AnalysisSeverity.warning,
          title: crestDelta > 0
              ? 'Mix is more dynamic'
              : 'Mix is more compressed',
          detail:
              'Crest factor differs by ${crestDelta.abs().toStringAsFixed(1)} dB.',
          action: crestDelta > 0
              ? 'Use light bus compression or parallel density if the reference feels more forward.'
              : 'Ease compression/limiting so drums and consonants breathe like the reference.',
          delta: crestDelta,
        ),
      );
    }

    if (truePeakDelta > 1.0) {
      findings.add(
        ReferenceFinding(
          severity: AnalysisSeverity.warning,
          title: 'Peak headroom is hotter',
          detail:
              'True peak is ${truePeakDelta.toStringAsFixed(1)} dB above the reference.',
          action:
              'Lower output ceiling or reduce input trim before codec-sensitive exports.',
          delta: truePeakDelta,
        ),
      );
    }

    for (final band in const [
      'sub',
      'bass',
      'lowMid',
      'mid',
      'presence',
      'harsh',
      'air',
    ]) {
      final mixValue = report.spectrum.bands[band] ?? 0;
      final refValue = referenceSpectrum.bands[band] ?? 0;
      final delta = mixValue - refValue;
      if (delta.abs() < .035) continue;
      findings.add(
        ReferenceFinding(
          severity: delta.abs() > .08
              ? AnalysisSeverity.critical
              : AnalysisSeverity.warning,
          title:
              '${_bandLabel(band)} ${delta > 0 ? 'above' : 'below'} reference',
          detail:
              '${_bandLabel(band)} energy is ${(delta.abs() * 100).toStringAsFixed(1)} percentage points ${delta > 0 ? 'higher' : 'lower'} than ${reference.name}.',
          action: _bandAction(band, delta),
          delta: delta,
        ),
      );
    }

    final penalty = findings.fold<double>(0, (total, finding) {
      final severityPenalty = finding.severity == AnalysisSeverity.critical
          ? 11.0
          : 6.0;
      return total + severityPenalty + finding.delta.abs() * 35;
    });
    final score = (100 - penalty).clamp(0, 100).toDouble();

    if (findings.isEmpty) {
      findings.add(
        ReferenceFinding(
          severity: AnalysisSeverity.good,
          title: 'Reference match is close',
          detail:
              'Loudness, dynamics, peak headroom, and broad tonal balance are in range.',
          action:
              'Use level-matched A/B listening and make only small taste-based moves.',
          delta: 0,
        ),
      );
    }

    return ReferenceComparison(
      referenceName: reference.name,
      metrics: referenceMetrics,
      spectrum: referenceSpectrum,
      matchScore: score,
      loudnessDelta: loudnessDelta,
      crestDelta: crestDelta,
      truePeakDelta: truePeakDelta,
      findings: findings.take(7).toList(),
    );
  }

  String _bandLabel(String band) {
    const labels = {
      'sub': 'Sub',
      'bass': 'Bass',
      'lowMid': 'Low-mid',
      'mid': 'Midrange',
      'presence': 'Presence',
      'harsh': 'Harshness',
      'air': 'Air',
    };
    return labels[band] ?? band;
  }

  String _bandAction(String band, double delta) {
    final above = delta > 0;
    switch (band) {
      case 'sub':
        return above
            ? 'High-pass inaudible rumble and tighten 35-70 Hz.'
            : 'Add controlled sub support or reduce masking above the bass fundamental.';
      case 'bass':
        return above
            ? 'Reduce 70-140 Hz buildup or sidechain bass against kick.'
            : 'Add low-end weight with harmonic bass saturation before boosting.';
      case 'lowMid':
        return above
            ? 'Cut 220-350 Hz broadly on dense buses.'
            : 'Restore body around 180-300 Hz if the mix feels thin.';
      case 'mid':
        return above
            ? 'Check honk around 700 Hz-1.5 kHz.'
            : 'Add musical midrange so the mix translates on small speakers.';
      case 'presence':
        return above
            ? 'Tame 2.5-4.5 kHz on vocals, guitars, or synths.'
            : 'Lift vocal/instrument presence around 3 kHz.';
      case 'harsh':
        return above
            ? 'Use dynamic EQ around 5-8 kHz before adding air.'
            : 'Add brightness with a shelf only after level matching.';
      case 'air':
        return above
            ? 'Reduce excessive top shelf or hiss above 10 kHz.'
            : 'Add gentle air above 10 kHz if noise floor allows.';
      default:
        return above ? 'Reduce this range.' : 'Add this range carefully.';
    }
  }

  List<ArrangementSuggestion> buildArrangementSuggestions(
    AnalysisReport report,
  ) {
    final suggestions = <ArrangementSuggestion>[];
    if (report.conflicts.isNotEmpty) {
      suggestions.add(
        ArrangementSuggestion(
          'Create contrast before the hook',
          'Mute or filter one masking instrument for 4-8 bars, then return it when the vocal phrase lands.',
        ),
      );
    }
    if (report.timelineMarkers.isNotEmpty) {
      suggestions.add(
        ArrangementSuggestion(
          'Automate problem sections',
          'Use the timeline markers as automation points for clip gain, de-essing, or dynamic EQ.',
        ),
      );
    }
    suggestions.addAll([
      ArrangementSuggestion(
        'Energy map',
        'Keep verse density lower than chorus density so the master can feel louder without only using limiting.',
      ),
      ArrangementSuggestion(
        'Vocal focus pass',
        'Double or widen supporting vocals only in high-energy sections, not across the full arrangement.',
      ),
    ]);
    return suggestions.take(4).toList();
  }

  List<RepairAction> buildRepairActions(AnalysisReport report) {
    final actions = <RepairAction>[
      RepairAction(
        'Noise and room cleanup',
        report.metrics.noiseFloorDb > -52 ? 'Needed' : 'Optional',
        'Gate only silent gaps first; avoid over-smoothing the full performance.',
      ),
      RepairAction(
        'Click and crackle scan',
        report.timelineMarkers.any((marker) => marker.title.contains('Harsh'))
            ? 'Recommended'
            : 'Optional',
        'Search short bright spikes before broad high-frequency reduction.',
      ),
      RepairAction(
        'Distortion recovery',
        report.metrics.clippedRatio > .001 ? 'Needed' : 'Healthy',
        'Lower clipped sections and use soft reconstruction before limiting.',
      ),
      RepairAction(
        'Phase and stereo safety',
        report.stems.length > 1 ? 'Recommended' : 'Optional',
        'Check mono translation after widening, especially for bass and lead vocals.',
      ),
    ];
    return actions;
  }

  List<double> renderEnhancedPreview(
    List<double> samples,
    int sampleRate,
    AnalysisMetrics metrics,
    SpectrumProfile spectrum,
    String target,
  ) {
    final targetPeak = target == 'Club' ? .96 : .89;
    final peak = math.pow(10, metrics.peakDb / 20).toDouble();
    final trim = peak > 0 ? math.min(1.6, targetPeak / peak) : 1.0;
    final lowMid = spectrum.bands['lowMid'] ?? 0;
    final presence = spectrum.bands['presence'] ?? 0;
    final harsh = spectrum.bands['harsh'] ?? 0;
    final mudCutDb = lowMid > .18 ? -2.8 : -1.1;
    final clarityBoostDb = presence < .2 ? 2.0 : .7;
    final harshCutDb = harsh > .1 ? -2.2 : -.6;
    final drive = target == 'Club' ? 1.22 : 1.08;
    final compressionThreshold = target == 'Podcast' ? -20.0 : -15.5;
    final compressionRatio = target == 'Club' ? 2.8 : 2.1;

    var processed = samples.map((sample) => sample * trim).toList();
    processed = _biquadHighPass(processed, sampleRate, 35, .707);
    processed = _biquadPeaking(processed, sampleRate, 280, .85, mudCutDb);
    processed = _biquadPeaking(
      processed,
      sampleRate,
      3200,
      1.0,
      clarityBoostDb,
    );
    processed = _biquadPeaking(processed, sampleRate, 6500, 1.3, harshCutDb);
    processed = _compress(
      processed,
      thresholdDb: compressionThreshold,
      ratio: compressionRatio,
      makeupDb: target == 'Club' ? 2.2 : 1.2,
    );
    processed = processed.map((sample) => _saturate(sample, drive)).toList();
    processed = _truePeakLimit(processed, ceiling: targetPeak);
    return processed;
  }

  List<double> renderRepairPreview(
    List<double> samples,
    int sampleRate,
    AnalysisMetrics metrics,
  ) {
    if (samples.isEmpty) return const [];
    final dc = samples.reduce((a, b) => a + b) / samples.length;
    var repaired = samples.map((sample) => sample - dc).toList();
    repaired = _repairClicks(repaired);
    repaired = _biquadHighPass(repaired, sampleRate, 28, .707);
    repaired = _noiseGate(
      repaired,
      thresholdDb: math.max(metrics.noiseFloorDb + 8, -58),
      floorGain: .18,
    );
    repaired = repaired.map((sample) => _saturate(sample, 1.04)).toList();
    repaired = _truePeakLimit(repaired, ceiling: .92);
    repaired = repaired
        .map((sample) => sample.clamp(-.98, .98).toDouble())
        .toList();
    return repaired;
  }

  List<double> downsample(List<double> samples, int size) {
    final step = math.max(1, samples.length ~/ size);
    return List<double>.generate(size, (index) {
      final start = index * step;
      final end = math.min(samples.length, start + step);
      var peak = 0.0;
      for (var i = start; i < end; i += 1) {
        if (samples[i].abs() > peak.abs()) {
          peak = samples[i];
        }
      }
      return peak;
    });
  }

  double _overlap(AudioStem first, AudioStem second, List<String> keys) {
    return keys.fold(
      0,
      (total, key) =>
          total +
          math.min(
            first.spectrum.bands[key] ?? 0,
            second.spectrum.bands[key] ?? 0,
          ),
    );
  }

  String? _bandFor(double frequency) {
    if (frequency >= 20 && frequency < 60) return 'sub';
    if (frequency >= 60 && frequency < 120) return 'bass';
    if (frequency >= 120 && frequency < 350) return 'lowMid';
    if (frequency >= 350 && frequency < 2000) return 'mid';
    if (frequency >= 2000 && frequency < 5000) return 'presence';
    if (frequency >= 5000 && frequency < 8000) return 'harsh';
    if (frequency >= 8000 && frequency < 16000) return 'air';
    return null;
  }

  double _db(double value) => 20 * math.log(math.max(value, 1e-12)) / math.ln10;

  List<double> _biquadHighPass(
    List<double> samples,
    int sampleRate,
    double frequency,
    double q,
  ) {
    final omega = 2 * math.pi * frequency / sampleRate;
    final cosOmega = math.cos(omega);
    final sinOmega = math.sin(omega);
    final alpha = sinOmega / (2 * q);
    final b0 = (1 + cosOmega) / 2;
    final b1 = -(1 + cosOmega);
    final b2 = (1 + cosOmega) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * cosOmega;
    final a2 = 1 - alpha;
    return _applyBiquad(samples, b0, b1, b2, a0, a1, a2);
  }

  List<double> _biquadPeaking(
    List<double> samples,
    int sampleRate,
    double frequency,
    double q,
    double gainDb,
  ) {
    final amplitude = math.pow(10, gainDb / 40).toDouble();
    final omega = 2 * math.pi * frequency / sampleRate;
    final cosOmega = math.cos(omega);
    final sinOmega = math.sin(omega);
    final alpha = sinOmega / (2 * q);
    final b0 = 1 + alpha * amplitude;
    final b1 = -2 * cosOmega;
    final b2 = 1 - alpha * amplitude;
    final a0 = 1 + alpha / amplitude;
    final a1 = -2 * cosOmega;
    final a2 = 1 - alpha / amplitude;
    return _applyBiquad(samples, b0, b1, b2, a0, a1, a2);
  }

  List<double> _applyBiquad(
    List<double> samples,
    double b0,
    double b1,
    double b2,
    double a0,
    double a1,
    double a2,
  ) {
    var x1 = 0.0;
    var x2 = 0.0;
    var y1 = 0.0;
    var y2 = 0.0;
    final output = List<double>.filled(samples.length, 0);
    for (var i = 0; i < samples.length; i += 1) {
      final x0 = samples[i];
      final y0 =
          (b0 / a0) * x0 +
          (b1 / a0) * x1 +
          (b2 / a0) * x2 -
          (a1 / a0) * y1 -
          (a2 / a0) * y2;
      output[i] = y0;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
    }
    return output;
  }

  List<double> _repairClicks(List<double> samples) {
    if (samples.length < 5) return samples;
    final output = List<double>.from(samples);
    for (var i = 2; i < samples.length - 2; i += 1) {
      final previous = samples[i - 1];
      final current = samples[i];
      final next = samples[i + 1];
      final localAverage =
          (samples[i - 2] + previous + next + samples[i + 2]) / 4;
      final spike = (current - localAverage).abs();
      final neighborMotion = (next - previous).abs();
      if (spike > .42 && spike > neighborMotion * 4) {
        output[i] = (previous + next) / 2;
      }
    }
    return output;
  }

  List<double> _noiseGate(
    List<double> samples, {
    required double thresholdDb,
    required double floorGain,
  }) {
    final threshold = math.pow(10, thresholdDb / 20).toDouble();
    var envelope = 0.0;
    const attack = .2;
    const release = .0015;
    return samples.map((sample) {
      final detector = sample.abs();
      envelope = detector > envelope
          ? envelope + (detector - envelope) * attack
          : envelope + (detector - envelope) * release;
      final gate = envelope < threshold ? floorGain : 1.0;
      return sample * gate;
    }).toList();
  }

  List<double> _compress(
    List<double> samples, {
    required double thresholdDb,
    required double ratio,
    required double makeupDb,
  }) {
    final makeup = math.pow(10, makeupDb / 20).toDouble();
    var envelope = 0.0;
    const attack = .16;
    const release = .006;
    return samples.map((sample) {
      final detector = sample.abs();
      envelope = detector > envelope
          ? envelope + (detector - envelope) * attack
          : envelope + (detector - envelope) * release;
      final envelopeDb = _db(envelope);
      final overDb = math.max(0, envelopeDb - thresholdDb);
      final reductionDb = overDb - overDb / ratio;
      final gain = math.pow(10, -reductionDb / 20).toDouble();
      return sample * gain * makeup;
    }).toList();
  }

  double _saturate(double sample, double drive) {
    return _tanh(sample * drive) / _tanh(drive);
  }

  List<double> _truePeakLimit(List<double> samples, {required double ceiling}) {
    return samples.map((sample) {
      if (sample.abs() <= ceiling) return sample;
      final sign = sample < 0 ? -1.0 : 1.0;
      final excess = sample.abs() - ceiling;
      return sign * (ceiling + excess / (1 + excess * 12));
    }).toList();
  }

  double _tanh(double value) {
    final exp = math.exp(value * 2);
    return (exp - 1) / (exp + 1);
  }

  void _fft(List<double> real, List<double> imag) {
    final n = real.length;
    for (var i = 1, j = 0; i < n; i += 1) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final realTemp = real[i];
        final imagTemp = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = realTemp;
        imag[j] = imagTemp;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wLenReal = math.cos(angle);
      final wLenImag = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var wReal = 1.0;
        var wImag = 0.0;
        for (var j = 0; j < len ~/ 2; j += 1) {
          final oddReal =
              real[i + j + len ~/ 2] * wReal - imag[i + j + len ~/ 2] * wImag;
          final oddImag =
              real[i + j + len ~/ 2] * wImag + imag[i + j + len ~/ 2] * wReal;
          final evenReal = real[i + j];
          final evenImag = imag[i + j];
          real[i + j] = evenReal + oddReal;
          imag[i + j] = evenImag + oddImag;
          real[i + j + len ~/ 2] = evenReal - oddReal;
          imag[i + j + len ~/ 2] = evenImag - oddImag;
          final nextReal = wReal * wLenReal - wImag * wLenImag;
          wImag = wReal * wLenImag + wImag * wLenReal;
          wReal = nextReal;
        }
      }
    }
  }
}

class AnalysisReport {
  AnalysisReport({
    required this.fileName,
    required this.releaseTarget,
    required this.metrics,
    required this.spectrum,
    required this.timelineMarkers,
    required this.stems,
    required this.conflicts,
    required this.issues,
    required this.fixes,
    required this.plugins,
    required this.waveform,
    required this.mixSamples,
    required this.enhancedSamples,
    required this.sampleRate,
  });

  final String fileName;
  final String releaseTarget;
  final AnalysisMetrics metrics;
  final SpectrumProfile spectrum;
  final List<TimelineFinding> timelineMarkers;
  final List<AudioStem> stems;
  final List<StemConflict> conflicts;
  final List<AnalysisIssue> issues;
  final List<ProcessingStep> fixes;
  final List<PluginRecommendation> plugins;
  final List<double> waveform;
  final List<double> mixSamples;
  final List<double> enhancedSamples;
  final int sampleRate;
}

class AnalysisMetrics {
  AnalysisMetrics({
    required this.peakDb,
    required this.truePeakDb,
    required this.loudnessDb,
    required this.lufsApprox,
    required this.noiseFloorDb,
    required this.crestFactor,
    required this.clippedRatio,
  });

  final double peakDb;
  final double truePeakDb;
  final double loudnessDb;
  final double lufsApprox;
  final double noiseFloorDb;
  final double crestFactor;
  final double clippedRatio;
}

class SpectrumProfile {
  SpectrumProfile({required this.bands, required this.visualSpectrum});

  final Map<String, double> bands;
  final List<double> visualSpectrum;
}

class AudioStem {
  AudioStem({
    required this.name,
    required this.role,
    required this.samples,
    required this.sampleRate,
    required this.metrics,
    required this.spectrum,
  });

  final String name;
  final String role;
  final List<double> samples;
  final int sampleRate;
  final AnalysisMetrics metrics;
  final SpectrumProfile spectrum;
}

class ImportedAudio {
  ImportedAudio({
    required this.name,
    required this.sampleRate,
    required this.samples,
  });

  final String name;
  final int sampleRate;
  final List<double> samples;
}

class AnalysisIssue {
  AnalysisIssue({
    required this.severity,
    required this.title,
    required this.evidence,
    required this.fix,
  });

  final AnalysisSeverity severity;
  final String title;
  final String evidence;
  final String fix;
}

class TimelineFinding {
  TimelineFinding(this.severity, this.startSec, this.title, this.detail);

  final AnalysisSeverity severity;
  final double startSec;
  final String title;
  final String detail;
}

class StemConflict {
  StemConflict(this.severity, this.title, this.evidence, this.fix);

  final AnalysisSeverity severity;
  final String title;
  final String evidence;
  final String fix;
}

class ProcessingStep {
  ProcessingStep(this.name, this.detail);

  final String name;
  final String detail;
}

class PluginRecommendation {
  PluginRecommendation(this.type, this.name, this.reason);

  final String type;
  final String name;
  final String reason;
}

class MasteringExport {
  MasteringExport(this.name, this.loudness, this.truePeak, this.note);

  final String name;
  final String loudness;
  final String truePeak;
  final String note;
}

class ReferenceComparison {
  ReferenceComparison({
    required this.referenceName,
    required this.metrics,
    required this.spectrum,
    required this.matchScore,
    required this.loudnessDelta,
    required this.crestDelta,
    required this.truePeakDelta,
    required this.findings,
  });

  final String referenceName;
  final AnalysisMetrics metrics;
  final SpectrumProfile spectrum;
  final double matchScore;
  final double loudnessDelta;
  final double crestDelta;
  final double truePeakDelta;
  final List<ReferenceFinding> findings;
}

class ReferenceFinding {
  ReferenceFinding({
    required this.severity,
    required this.title,
    required this.detail,
    required this.action,
    required this.delta,
  });

  final AnalysisSeverity severity;
  final String title;
  final String detail;
  final String action;
  final double delta;
}

class ArrangementSuggestion {
  ArrangementSuggestion(this.title, this.detail);

  final String title;
  final String detail;
}

class RepairAction {
  RepairAction(this.name, this.status, this.detail);

  final String name;
  final String status;
  final String detail;
}

class _Window {
  _Window(this.startSec, this.rmsDb, this.peakDb, this.zeroCrossingRate);

  final double startSec;
  final double rmsDb;
  final double peakDb;
  final double zeroCrossingRate;
}

enum AnalysisSeverity { good, warning, critical }
