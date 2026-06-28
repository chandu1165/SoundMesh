import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:io';

import 'package:auralyze_app/audio_analysis.dart';
import 'package:auralyze_app/report_exporter.dart';
import 'package:auralyze_app/sound_generator.dart';
import 'package:auralyze_app/wav_decoder.dart';

void main() {
  final bytes = _makeSineWav();
  final wav = WavDecoder().decode('vocal_demo.wav', bytes);
  final analyzer = AuralyzeAnalyzer();
  final report = analyzer.analyzeFiles(
    files: [
      ImportedAudio(
        name: wav.name,
        sampleRate: wav.sampleRate,
        samples: wav.samples,
      ),
    ],
    releaseTarget: 'Streaming',
  );
  final referenceWav = WavDecoder().decode(
    'reference_master.wav',
    _makeSineWav(frequency: 120),
  );
  final comparison = analyzer.compareWithReference(
    report: report,
    reference: ImportedAudio(
      name: referenceWav.name,
      sampleRate: referenceWav.sampleRate,
      samples: referenceWav.samples,
    ),
  );

  final checks = {
    'file': report.fileName == 'vocal_demo.wav',
    'peak': report.metrics.peakDb < 0,
    'spectrum': report.spectrum.visualSpectrum.isNotEmpty,
    'role': report.stems.first.role == 'vocal',
    'fixes': report.fixes.isNotEmpty,
    'plugins': report.plugins.isNotEmpty,
    'enhancedLength': report.enhancedSamples.length == report.mixSamples.length,
    'previewDiffers': _previewDiffers(report),
    'repair': _repairRenderOk(analyzer, report),
    'referenceName': comparison.referenceName == 'reference_master.wav',
    'referenceFindings': comparison.findings.isNotEmpty,
    'referenceScore':
        comparison.matchScore >= 0 && comparison.matchScore <= 100,
    'generatedSound': _generatedSoundOk(),
    'presetExport': _presetExportOk(report),
    'reaperScript': _reaperScriptOk(report),
    'roundTrip': _projectRoundTripOk(report),
  };
  final ok = checks.values.every((value) => value);

  stdout.writeln({
    'file': report.fileName,
    'role': report.stems.first.role,
    'peakDb': report.metrics.peakDb.toStringAsFixed(1),
    'fixes': report.fixes.length,
    'plugins': report.plugins.length,
    'referenceScore': comparison.matchScore.round(),
    'generated': 'ok',
    'checks': checks,
    'ok': ok,
  });

  if (!ok) {
    throw StateError('Analysis smoke test failed');
  }
}

bool _previewDiffers(AnalysisReport report) {
  var delta = 0.0;
  final limit = math.min(
    report.mixSamples.length,
    report.enhancedSamples.length,
  );
  for (var i = 0; i < limit; i += 512) {
    delta += (report.mixSamples[i] - report.enhancedSamples[i]).abs();
  }
  return delta > .001;
}

bool _repairRenderOk(AuralyzeAnalyzer analyzer, AnalysisReport report) {
  final repaired = analyzer.renderRepairPreview(
    report.mixSamples,
    report.sampleRate,
    report.metrics,
  );
  if (repaired.length != report.mixSamples.length) return false;
  var peak = 0.0;
  for (final sample in repaired) {
    peak = math.max(peak, sample.abs());
  }
  return peak > .001 && peak <= 1.0;
}

bool _projectRoundTripOk(AnalysisReport report) {
  final exporter = ReportExporter();
  final imported = exporter.reportFromJsonBytes(
    exporter.jsonReportBytes(report),
  );
  return imported.fileName == report.fileName &&
      imported.releaseTarget == report.releaseTarget &&
      imported.issues.length == report.issues.length &&
      imported.fixes.length == report.fixes.length &&
      imported.plugins.length == report.plugins.length;
}

bool _presetExportOk(AnalysisReport report) {
  final exporter = ReportExporter();
  final value = jsonDecode(
    String.fromCharCodes(exporter.presetJsonBytes(report)),
  );
  if (value is! Map<String, dynamic>) return false;
  final chain = value['chain'];
  return value['type'] == 'processing-preset' &&
      chain is List &&
      chain.length >= 6 &&
      chain.every((item) => item is Map && item['parameters'] is Map);
}

bool _reaperScriptOk(AnalysisReport report) {
  final script = utf8.decode(ReportExporter().reaperScriptBytes(report));
  return script.contains('TrackFX_AddByName') &&
      script.contains('GetSelectedTrack') &&
      script.contains('Auralyze suggested chain');
}

bool _generatedSoundOk() {
  final sound = PromptSoundGenerator().generate('futuristic laser');
  final peak = sound.samples.fold<double>(
    0,
    (current, sample) => math.max(current, sample.abs()),
  );
  return sound.name.endsWith('.wav') &&
      sound.sampleRate == 44100 &&
      sound.samples.length > 20000 &&
      sound.layers.isNotEmpty &&
      peak > .1 &&
      peak <= 1.0;
}

Uint8List _makeSineWav({double frequency = 3200}) {
  const sampleRate = 44100;
  const seconds = 1;
  const sampleCount = sampleRate * seconds;
  const channels = 1;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  const dataSize = sampleCount * channels * bytesPerSample;
  final bytes = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(bytes);

  void writeString(int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeString(36, 'data');
  data.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < sampleCount; i += 1) {
    final t = i / sampleRate;
    final value = (0.4 * math.sin(2 * math.pi * frequency * t) * 32767).round();
    data.setInt16(44 + i * 2, value, Endian.little);
  }

  return bytes;
}
