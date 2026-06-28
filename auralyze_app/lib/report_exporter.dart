import 'dart:convert';
import 'dart:typed_data';

import 'audio_analysis.dart';

class ReportExporter {
  Uint8List htmlReportBytes(AnalysisReport report) {
    return Uint8List.fromList(utf8.encode(_html(report)));
  }

  Uint8List jsonReportBytes(AnalysisReport report) {
    final payload = {
      'app': 'Auralyze',
      'version': 1,
      'fileName': report.fileName,
      'releaseTarget': report.releaseTarget,
      'sampleRate': report.sampleRate,
      'metrics': {
        'peakDb': report.metrics.peakDb,
        'truePeakDb': report.metrics.truePeakDb,
        'loudnessDb': report.metrics.loudnessDb,
        'lufsApprox': report.metrics.lufsApprox,
        'noiseFloorDb': report.metrics.noiseFloorDb,
        'crestFactor': report.metrics.crestFactor,
        'clippedRatio': report.metrics.clippedRatio,
      },
      'spectrum': {
        'bands': report.spectrum.bands,
        'visualSpectrum': report.spectrum.visualSpectrum,
      },
      'waveform': report.waveform,
      'hasEnhancedPreview': report.enhancedSamples.isNotEmpty,
      'issues': report.issues.map((issue) {
        return {
          'severity': issue.severity.name,
          'title': issue.title,
          'evidence': issue.evidence,
          'fix': issue.fix,
        };
      }).toList(),
      'timeline': report.timelineMarkers.map((marker) {
        return {
          'severity': marker.severity.name,
          'startSec': marker.startSec,
          'title': marker.title,
          'detail': marker.detail,
        };
      }).toList(),
      'conflicts': report.conflicts.map((conflict) {
        return {
          'severity': conflict.severity.name,
          'title': conflict.title,
          'evidence': conflict.evidence,
          'fix': conflict.fix,
        };
      }).toList(),
      'stems': report.stems.map((stem) {
        return {
          'name': stem.name,
          'role': stem.role,
          'peakDb': stem.metrics.peakDb,
          'truePeakDb': stem.metrics.truePeakDb,
          'loudnessDb': stem.metrics.loudnessDb,
          'lufsApprox': stem.metrics.lufsApprox,
          'noiseFloorDb': stem.metrics.noiseFloorDb,
          'crestFactor': stem.metrics.crestFactor,
          'clippedRatio': stem.metrics.clippedRatio,
          'spectrum': {
            'bands': stem.spectrum.bands,
            'visualSpectrum': stem.spectrum.visualSpectrum,
          },
        };
      }).toList(),
      'fixes': report.fixes
          .map((fix) => {'name': fix.name, 'detail': fix.detail})
          .toList(),
      'plugins': report.plugins
          .map(
            (plugin) => {
              'type': plugin.type,
              'name': plugin.name,
              'reason': plugin.reason,
            },
          )
          .toList(),
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  Uint8List presetJsonBytes(AnalysisReport report) {
    final parameters = _presetParameters(report);
    final payload = {
      'app': 'Auralyze',
      'type': 'processing-preset',
      'version': 1,
      'source': report.fileName,
      'releaseTarget': report.releaseTarget,
      'chain': [
        {
          'slot': 1,
          'processor': 'Input trim',
          'pluginType': 'gain',
          'parameters': {'gainDb': parameters['inputTrimDb']},
        },
        {
          'slot': 2,
          'processor': 'Sub cleanup',
          'pluginType': 'high_pass_filter',
          'parameters': {'frequencyHz': 35, 'slopeDbPerOctave': 24},
        },
        {
          'slot': 3,
          'processor': 'Mud control',
          'pluginType': 'parametric_eq',
          'parameters': {
            'frequencyHz': 280,
            'gainDb': parameters['mudGainDb'],
            'q': 0.9,
            'dynamic': true,
          },
        },
        {
          'slot': 4,
          'processor': 'Presence shaping',
          'pluginType': 'parametric_eq',
          'parameters': {
            'frequencyHz': 3200,
            'gainDb': parameters['presenceGainDb'],
            'q': 0.75,
          },
        },
        {
          'slot': 5,
          'processor': 'Harshness control',
          'pluginType': 'dynamic_eq',
          'parameters': {
            'frequencyHz': 6500,
            'gainDb': parameters['harshGainDb'],
            'q': 1.2,
          },
        },
        {
          'slot': 6,
          'processor': 'Bus compressor',
          'pluginType': 'compressor',
          'parameters': {
            'ratio': 2.0,
            'attackMs': 18,
            'releaseMs': 120,
            'thresholdDb': parameters['compressorThresholdDb'],
            'mixPercent': 65,
          },
        },
        {
          'slot': 7,
          'processor': 'True-peak limiter',
          'pluginType': 'limiter',
          'parameters': {
            'ceilingDbtp': parameters['limiterCeilingDb'],
            'targetLufs': parameters['targetLufs'],
          },
        },
      ],
      'suggestedPlugins': report.plugins
          .map(
            (plugin) => {
              'type': plugin.type,
              'name': plugin.name,
              'reason': plugin.reason,
            },
          )
          .toList(),
      'humanReadableSteps': report.fixes
          .map((fix) => {'name': fix.name, 'detail': fix.detail})
          .toList(),
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  Uint8List reaperScriptBytes(AnalysisReport report) {
    final chainText = report.fixes.indexed
        .map((entry) => '${entry.$1 + 1}. ${entry.$2.name}: ${entry.$2.detail}')
        .join(r'\n');
    final plugins = report.plugins
        .map((plugin) => plugin.name)
        .toSet()
        .toList();
    final pluginAdds = plugins
        .map((plugin) {
          final fxName = _reaperFxName(plugin);
          return "reaper.TrackFX_AddByName(track, ${_luaString(fxName)}, false, -1)";
        })
        .join('\n');
    final script =
        '''
-- Auralyze REAPER chain helper
-- Source: ${_luaComment(report.fileName)}
-- Target: ${_luaComment(report.releaseTarget)}

local track = reaper.GetSelectedTrack(0, 0)
if track == nil then
  track = reaper.GetTrack(0, 0)
end

if track == nil then
  reaper.ShowMessageBox("Select or create a track before running this Auralyze script.", "Auralyze", 0)
  return
end

reaper.Undo_BeginBlock()
$pluginAdds

local notes = ${_luaString('Auralyze chain for ${report.fileName}\\n$chainText')}
reaper.GetSetMediaTrackInfo_String(track, "P_EXT:AuralyzeChain", notes, true)
reaper.ShowMessageBox(notes, "Auralyze suggested chain", 0)
reaper.Undo_EndBlock("Apply Auralyze helper chain", -1)
''';
    return Uint8List.fromList(utf8.encode(script));
  }

  AnalysisReport reportFromJsonBytes(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Project JSON must be an object.');
    }
    if (value['app'] != 'Auralyze') {
      throw const FormatException('This is not an Auralyze project file.');
    }

    final metrics = _metrics(value['metrics']);
    final spectrum = _spectrum(value['spectrum']);
    final issues = _list(value['issues']).map((item) {
      return AnalysisIssue(
        severity: _severity(item['severity']),
        title: _string(item['title'], 'Saved issue'),
        evidence: _string(item['evidence'], 'Saved project evidence'),
        fix: _string(item['fix'], 'Review this saved issue.'),
      );
    }).toList();
    final timeline = _list(value['timeline']).map((item) {
      return TimelineFinding(
        _severity(item['severity']),
        _double(item['startSec']),
        _string(item['title'], 'Saved marker'),
        _string(item['detail'], 'Timeline marker from saved project.'),
      );
    }).toList();
    final conflicts = _list(value['conflicts']).map((item) {
      return StemConflict(
        _severity(item['severity']),
        _string(item['title'], 'Saved conflict'),
        _string(item['evidence'], 'Saved conflict evidence'),
        _string(item['fix'], 'Review this saved conflict.'),
      );
    }).toList();
    final stems = _list(value['stems']).map((item) {
      return AudioStem(
        name: _string(item['name'], 'saved_stem.wav'),
        role: _string(item['role'], 'music'),
        samples: const [],
        sampleRate: _int(value['sampleRate'], 44100),
        metrics: AnalysisMetrics(
          peakDb: _double(item['peakDb'], -60),
          truePeakDb: _double(item['truePeakDb'], _double(item['peakDb'], -60)),
          loudnessDb: _double(
            item['loudnessDb'],
            _double(item['lufsApprox'], -60) + .7,
          ),
          lufsApprox: _double(item['lufsApprox'], -60),
          noiseFloorDb: _double(item['noiseFloorDb'], -90),
          crestFactor: _double(item['crestFactor'], 0),
          clippedRatio: _double(item['clippedRatio']),
        ),
        spectrum: _spectrum(item['spectrum']),
      );
    }).toList();
    final fixes = _list(value['fixes']).map((item) {
      return ProcessingStep(
        _string(item['name'], 'Saved step'),
        _string(item['detail'], 'Saved processing step.'),
      );
    }).toList();
    final plugins = _list(value['plugins']).map((item) {
      return PluginRecommendation(
        _string(item['type'], 'Tool'),
        _string(item['name'], 'Recommended plugin'),
        _string(item['reason'], 'Saved recommendation.'),
      );
    }).toList();

    return AnalysisReport(
      fileName: _string(value['fileName'], 'Imported project'),
      releaseTarget: _string(value['releaseTarget'], 'Streaming'),
      metrics: metrics,
      spectrum: spectrum,
      timelineMarkers: timeline,
      stems: stems,
      conflicts: conflicts,
      issues: issues,
      fixes: fixes,
      plugins: plugins,
      waveform: _doubleList(value['waveform'], fallbackLength: 180),
      mixSamples: const [],
      enhancedSamples: const [],
      sampleRate: _int(value['sampleRate'], 44100),
    );
  }

  String _html(AnalysisReport report) {
    final issueHtml = report.issues.map((issue) {
      return '<article class="${issue.severity.name}"><h3>${_e(issue.title)}</h3><p><strong>Evidence:</strong> ${_e(issue.evidence)}</p><p><strong>Fix:</strong> ${_e(issue.fix)}</p></article>';
    }).join();
    final timelineHtml = report.timelineMarkers.map((marker) {
      return '<article class="${marker.severity.name}"><h3>${_formatTime(marker.startSec)} - ${_e(marker.title)}</h3><p>${_e(marker.detail)}</p></article>';
    }).join();
    final fixesHtml = report.fixes
        .map(
          (fix) =>
              '<li><strong>${_e(fix.name)}:</strong> ${_e(fix.detail)}</li>',
        )
        .join();
    final pluginsHtml = report.plugins
        .map(
          (plugin) =>
              '<li><strong>${_e(plugin.type)} / ${_e(plugin.name)}:</strong> ${_e(plugin.reason)}</li>',
        )
        .join();

    return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Auralyze Report - ${_e(report.fileName)}</title>
<style>
body{margin:0;background:#f7f5ef;color:#1d2525;font-family:Arial,sans-serif;line-height:1.5}
main{width:min(980px,calc(100% - 32px));margin:0 auto;padding:32px 0}
section{background:white;border:1px solid #d9ddd5;border-radius:8px;padding:18px;margin:14px 0}
h1{font-size:42px;margin:0 0 4px} h2{margin:0 0 12px}
article{background:#fbfbf8;border-left:5px solid #0b7a75;border-radius:8px;padding:12px;margin:10px 0}
.warning{border-left-color:#b7791f}.critical{border-left-color:#db5f4b}.muted{color:#65706e}
td{padding:7px 12px;border-bottom:1px solid #e5e7df}td:first-child{font-weight:bold;color:#65706e}
</style>
</head>
<body>
<main>
<p class="muted">Auralyze audio diagnosis report</p>
<h1>${_e(report.fileName)}</h1>
<p class="muted">Release target: ${_e(report.releaseTarget)}</p>
<section><h2>Metrics</h2><table>
<tr><td>Peak</td><td>${report.metrics.peakDb.toStringAsFixed(1)} dBFS</td></tr>
<tr><td>True peak</td><td>${report.metrics.truePeakDb.toStringAsFixed(1)} dBTP</td></tr>
<tr><td>Loudness</td><td>${report.metrics.lufsApprox.toStringAsFixed(1)} LUFS*</td></tr>
<tr><td>Noise floor</td><td>${report.metrics.noiseFloorDb.toStringAsFixed(1)} dB</td></tr>
<tr><td>Dynamics</td><td>${report.metrics.crestFactor.toStringAsFixed(1)} dB</td></tr>
</table></section>
<section><h2>Diagnosis</h2>${issueHtml.isEmpty ? '<p>No major issues detected.</p>' : issueHtml}</section>
<section><h2>Timeline</h2>${timelineHtml.isEmpty ? '<p>No timeline markers.</p>' : timelineHtml}</section>
<section><h2>Processing Chain</h2><ul>$fixesHtml</ul></section>
<section><h2>Recommended Tools</h2><ul>$pluginsHtml</ul></section>
</main>
</body>
</html>
''';
  }

  Map<String, double> _presetParameters(AnalysisReport report) {
    final lowMid = report.spectrum.bands['lowMid'] ?? 0;
    final presence = report.spectrum.bands['presence'] ?? 0;
    final harsh = report.spectrum.bands['harsh'] ?? 0;
    final target = _targetLufs(report.releaseTarget);
    final limiterCeiling = switch (report.releaseTarget) {
      'Club' => -0.3,
      'Cinema' => -2.0,
      'Podcast' => -1.5,
      _ => -1.0,
    };
    final loudnessGap = target - report.metrics.lufsApprox;
    return {
      'inputTrimDb': report.metrics.truePeakDb > -1 ? -2.0 : 0.0,
      'mudGainDb': lowMid > .18 ? -2.5 : -1.0,
      'presenceGainDb': presence < .22 ? 1.8 : 0.6,
      'harshGainDb': harsh > .12 ? -2.2 : -0.6,
      'compressorThresholdDb': (report.metrics.loudnessDb - 8)
          .clamp(-34.0, -10.0)
          .toDouble(),
      'limiterCeilingDb': limiterCeiling,
      'targetLufs': target,
      'suggestedLimiterInputDb': loudnessGap.clamp(-4.0, 5.0).toDouble(),
    };
  }

  double _targetLufs(String target) {
    return switch (target) {
      'Club' => -9.0,
      'Podcast' => -16.0,
      'Cinema' => -23.0,
      'YouTube' => -14.0,
      'Streaming' => -14.0,
      _ => -14.0,
    };
  }

  String _reaperFxName(String plugin) {
    final lower = plugin.toLowerCase();
    if (lower.contains('compress')) return 'ReaComp (Cockos)';
    if (lower.contains('limit')) return 'ReaLimit (Cockos)';
    if (lower.contains('eq')) return 'ReaEQ (Cockos)';
    if (lower.contains('sidechain')) return 'ReaEQ (Cockos)';
    return 'ReaEQ (Cockos)';
  }

  String _luaString(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  String _luaComment(String value) {
    return value.replaceAll('\n', ' ').replaceAll('\r', ' ');
  }

  String _formatTime(double seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds.floor() % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  String _e(Object? value) {
    return '$value'
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }

  AnalysisMetrics _metrics(Object? value) {
    final map = value is Map<String, dynamic> ? value : <String, dynamic>{};
    return AnalysisMetrics(
      peakDb: _double(map['peakDb'], -60),
      truePeakDb: _double(map['truePeakDb'], _double(map['peakDb'], -60)),
      loudnessDb: _double(
        map['loudnessDb'],
        _double(map['lufsApprox'], -60) + .7,
      ),
      lufsApprox: _double(map['lufsApprox'], -60),
      noiseFloorDb: _double(map['noiseFloorDb'], -90),
      crestFactor: _double(map['crestFactor'], 0),
      clippedRatio: _double(map['clippedRatio']),
    );
  }

  SpectrumProfile _spectrum(Object? value) {
    final map = value is Map<String, dynamic> ? value : <String, dynamic>{};
    final rawBands = map['bands'] is Map<String, dynamic>
        ? map['bands'] as Map<String, dynamic>
        : <String, dynamic>{};
    final bands = {
      'sub': _double(rawBands['sub']),
      'bass': _double(rawBands['bass']),
      'lowMid': _double(rawBands['lowMid']),
      'mid': _double(rawBands['mid']),
      'presence': _double(rawBands['presence']),
      'harsh': _double(rawBands['harsh']),
      'air': _double(rawBands['air']),
    };
    return SpectrumProfile(
      bands: bands,
      visualSpectrum: _doubleList(map['visualSpectrum'], fallbackLength: 64),
    );
  }

  List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  List<double> _doubleList(Object? value, {required int fallbackLength}) {
    if (value is List) {
      final values = value
          .whereType<num>()
          .map((item) => item.toDouble())
          .toList();
      if (values.isNotEmpty) return values;
    }
    return List<double>.filled(fallbackLength, 0);
  }

  AnalysisSeverity _severity(Object? value) {
    final name = _string(value, 'warning');
    return AnalysisSeverity.values.firstWhere(
      (severity) => severity.name == name,
      orElse: () => AnalysisSeverity.warning,
    );
  }

  String _string(Object? value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  double _double(Object? value, [double fallback = 0]) {
    return value is num ? value.toDouble() : fallback;
  }

  int _int(Object? value, int fallback) {
    return value is num ? value.round() : fallback;
  }
}
