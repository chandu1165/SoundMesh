import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'audio_analysis.dart' as engine;
import 'report_exporter.dart';
import 'sound_generator.dart';
import 'wav_decoder.dart';
import 'wav_encoder.dart';

void main() {
  runApp(const AuralyzeApp());
}

class AuralyzeApp extends StatelessWidget {
  const AuralyzeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Auralyze',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B7A75),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F5EF),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFF1D2525),
          displayColor: const Color(0xFF1D2525),
        ),
      ),
      home: const AuralyzeHome(),
    );
  }
}

class AuralyzeHome extends StatefulWidget {
  const AuralyzeHome({super.key});

  @override
  State<AuralyzeHome> createState() => _AuralyzeHomeState();
}

class _AuralyzeHomeState extends State<AuralyzeHome> {
  static const String backendBaseUrl = String.fromEnvironment(
    'AURALYZE_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8788',
  );
  final engine.AuralyzeAnalyzer analyzer = engine.AuralyzeAnalyzer();
  final PromptSoundGenerator soundGenerator = PromptSoundGenerator();
  final AudioPlayer previewPlayer = AudioPlayer(playerId: 'auralyze-preview');
  String contentType = 'Music mix';
  String releaseTarget = 'Streaming';
  String projectName = 'Neon Verse Mix';
  List<engine.ImportedAudio> currentImportedFiles = [];
  engine.ImportedAudio? currentReferenceFile;
  engine.ReferenceComparison? referenceComparison;
  bool analyzed = true;
  bool analyzingFiles = false;
  bool analyzingReference = false;
  bool separatingStems = false;
  bool checkingSystem = false;
  bool previewPlaying = false;
  String previewMode = 'Enhanced';
  String playingPreviewMode = '';
  String statusMessage = 'Demo analysis ready';
  String backendStatus = 'Not checked';
  String aiStatus = 'Not checked';
  String ragStatus = 'Not checked';
  String formatStatus = 'Not checked';
  String separationStatus = 'Not checked';
  String authStatus = 'Not checked';
  String billingStatus = 'Not checked';
  String storageStatus = 'Not checked';
  String accountStatus = 'Not signed in';
  String cloudProjectStatus = 'Cloud projects not loaded';
  List<CloudProject> cloudProjects = [];
  String copilotAnswer =
      'Ask about mud, vocals, kick/bass conflicts, loudness, plugins, or what to fix first.';
  String soundDesignerAnswer =
      'Describe a sound or vibe and Auralyze will turn it into a production chain.';
  GeneratedSound? generatedSound;
  String knowledgeStatus =
      'Add your own mixing notes and the copilot will retrieve them.';
  String sampleQuery = 'dark cinematic impacts';
  late engine.AnalysisReport report;
  final TextEditingController copilotController = TextEditingController();
  final TextEditingController soundDesignerController = TextEditingController(
    text: 'Make this mix darker and more cinematic',
  );
  final TextEditingController knowledgeTitleController = TextEditingController(
    text: 'My vocal mixing rule',
  );
  final TextEditingController knowledgeTagsController = TextEditingController(
    text: 'vocal, clarity, mud',
  );
  final TextEditingController knowledgeTextController = TextEditingController(
    text:
        'Before boosting vocal presence, cut guitars or keys around 250 Hz and 3 kHz if they mask the lead.',
  );
  final TextEditingController sampleSearchController = TextEditingController(
    text: 'dark cinematic impacts',
  );
  final TextEditingController accountEmailController = TextEditingController(
    text: 'local@auralyze.dev',
  );

  List<Diagnosis> get issues =>
      report.issues.map(Diagnosis.fromEngine).toList();
  List<TimelineMarker> get markers =>
      report.timelineMarkers.map(TimelineMarker.fromEngine).toList();
  List<StemTrack> get stems => report.stems.map(StemTrack.fromEngine).toList();
  List<engine.MasteringExport> get masteringExports =>
      analyzer.buildMasteringExports(report);
  List<engine.ArrangementSuggestion> get arrangementSuggestions =>
      analyzer.buildArrangementSuggestions(report);
  List<engine.RepairAction> get repairActions =>
      analyzer.buildRepairActions(report);
  List<SampleMatch> get sampleMatches => _sampleMatches(sampleQuery);

  @override
  void initState() {
    super.initState();
    report = analyzer.analyzeDemo(releaseTarget: releaseTarget);
    previewPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => previewPlaying = state == PlayerState.playing);
    });
    previewPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        previewPlaying = false;
        playingPreviewMode = '';
        statusMessage = 'Preview finished';
      });
    });
    refreshSystemStatus();
  }

  void runDemoAnalysis() {
    setState(() {
      currentImportedFiles = [];
      report = analyzer.analyzeDemo(releaseTarget: releaseTarget);
      _refreshReferenceComparison();
      projectName = 'Neon Verse Mix';
      analyzed = true;
      statusMessage = 'Demo analysis ready';
      copilotAnswer =
          'Demo refreshed. Ask what to fix first, or ask about any diagnosis item.';
    });
  }

  void applyReleaseTarget(String value) {
    setState(() {
      releaseTarget = value;
      if (currentImportedFiles.isNotEmpty) {
        report = analyzer.analyzeFiles(
          files: currentImportedFiles,
          releaseTarget: releaseTarget,
        );
        _refreshReferenceComparison();
        statusMessage = '$releaseTarget target rendered for $projectName';
      } else {
        report = analyzer.analyzeDemo(releaseTarget: releaseTarget);
        _refreshReferenceComparison();
        projectName = 'Neon Verse Mix';
        statusMessage = '$releaseTarget target rendered for demo audio';
      }
      previewMode = 'Enhanced';
      copilotAnswer =
          'The $releaseTarget target is active. Export the enhanced WAV to use this master version.';
    });
  }

  void applyMasteringTarget(String name) {
    const targetMap = {
      'Spotify': 'Streaming',
      'YouTube': 'YouTube',
      'Club': 'Club',
      'Podcast': 'Podcast',
      'Cinema': 'Cinema',
    };
    applyReleaseTarget(targetMap[name] ?? name);
  }

  void _refreshReferenceComparison() {
    final reference = currentReferenceFile;
    referenceComparison = reference == null
        ? null
        : analyzer.compareWithReference(report: report, reference: reference);
  }

  @override
  void dispose() {
    previewPlayer.dispose();
    copilotController.dispose();
    soundDesignerController.dispose();
    knowledgeTitleController.dispose();
    knowledgeTagsController.dispose();
    knowledgeTextController.dispose();
    sampleSearchController.dispose();
    accountEmailController.dispose();
    super.dispose();
  }

  Future<void> chooseAndAnalyzeFiles() async {
    setState(() {
      analyzingFiles = true;
      statusMessage = 'Reading audio files...';
    });
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          statusMessage = 'File selection cancelled';
          analyzingFiles = false;
        });
        return;
      }

      final imported = <engine.ImportedAudio>[];
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw WavDecodeException('Could not read ${file.name}.');
        }
        setState(() => statusMessage = 'Reading ${file.name}...');
        final wavBytes = await _wavBytesForUpload(file.name, bytes);
        final wav = WavDecoder().decode(file.name, wavBytes);
        imported.add(
          engine.ImportedAudio(
            name: wav.name,
            sampleRate: wav.sampleRate,
            samples: wav.samples,
          ),
        );
      }

      setState(() {
        currentImportedFiles = imported;
        report = analyzer.analyzeFiles(
          files: imported,
          releaseTarget: releaseTarget,
        );
        _refreshReferenceComparison();
        projectName = result.files.length == 1
            ? result.files.first.name
            : '${result.files.length} audio stems';
        statusMessage =
            'Analyzed ${result.files.length} audio file${result.files.length == 1 ? '' : 's'}';
        analyzingFiles = false;
        analyzed = true;
      });
    } catch (error) {
      setState(() {
        statusMessage = 'Import failed: $error';
        analyzingFiles = false;
      });
    }
  }

  Future<void> chooseAndSeparateSong() async {
    setState(() {
      separatingStems = true;
      statusMessage = 'Choosing song for source separation...';
    });
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          separatingStems = false;
          statusMessage = 'Stem separation cancelled';
        });
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw WavDecodeException('Could not read ${file.name}.');
      }
      setState(
        () => statusMessage = 'Separating ${file.name} with backend engine...',
      );
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$backendBaseUrl/api/stem-separation/separate'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: file.name),
      );
      final streamed = await request.send().timeout(
        const Duration(minutes: 16),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final engineName = payload['engine'] as String? ?? 'backend engine';
      final fallback = payload['fallback'] == true;
      final rawStems = payload['stems'] as List<dynamic>? ?? [];
      final separated = <engine.ImportedAudio>[];
      for (final item in rawStems.whereType<Map<String, dynamic>>()) {
        final name = item['name'] as String? ?? 'separated_stem.wav';
        final encoded = item['bytesBase64'] as String? ?? '';
        if (encoded.isEmpty) continue;
        final wav = WavDecoder().decode(name, base64Decode(encoded));
        separated.add(
          engine.ImportedAudio(
            name: wav.name,
            sampleRate: wav.sampleRate,
            samples: wav.samples,
          ),
        );
      }
      if (separated.isEmpty) {
        throw StateError('No separated stems were returned by the backend.');
      }
      setState(() {
        currentImportedFiles = separated;
        report = analyzer.analyzeFiles(
          files: separated,
          releaseTarget: releaseTarget,
        );
        _refreshReferenceComparison();
        projectName = '${file.name} separated';
        separatingStems = false;
        analyzed = true;
        previewMode = 'Enhanced';
        statusMessage =
            '${fallback ? 'Approximate' : 'Separated'} and analyzed ${separated.length} stems with $engineName';
        copilotAnswer = fallback
            ? 'Free hosted stem fallback complete. These are approximate frequency-shaped stems, useful for diagnosis but less clean than Demucs.'
            : 'Stem separation complete. Ask about vocal masking, drum/bass balance, or what to fix first.';
      });
    } catch (error) {
      setState(() {
        separatingStems = false;
        statusMessage = 'Stem separation failed: $error';
        copilotAnswer =
            'Stem separation needs either Demucs or the free FFmpeg fallback on the backend. Check System status, then restart the product if setup changed.';
      });
    }
  }

  Future<void> chooseReferenceFile() async {
    setState(() {
      analyzingReference = true;
      statusMessage = 'Reading reference audio...';
    });
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          statusMessage = 'Reference selection cancelled';
          analyzingReference = false;
        });
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw WavDecodeException('Could not read ${file.name}.');
      }
      final wavBytes = await _wavBytesForUpload(file.name, bytes);
      final wav = WavDecoder().decode(file.name, wavBytes);
      final reference = engine.ImportedAudio(
        name: wav.name,
        sampleRate: wav.sampleRate,
        samples: wav.samples,
      );
      setState(() {
        currentReferenceFile = reference;
        _refreshReferenceComparison();
        analyzingReference = false;
        statusMessage = 'Reference matched against ${reference.name}';
        copilotAnswer =
            'Reference loaded. Ask why the mix differs from ${reference.name}, or follow the reference match moves.';
      });
    } catch (error) {
      setState(() {
        statusMessage = 'Reference import failed: $error';
        analyzingReference = false;
      });
    }
  }

  Future<Uint8List> _wavBytesForUpload(String name, Uint8List bytes) async {
    final extension = name.split('.').last.toLowerCase();
    if (extension == 'wav') return bytes;
    setState(() => statusMessage = 'Transcoding $name with FFmpeg...');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$backendBaseUrl/api/audio/transcode'),
    );
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: name),
    );
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw WavDecodeException(
      'Could not transcode $name. ${response.statusCode}: ${response.body}',
    );
  }

  Future<void> exportCurrentWav() async {
    setState(() => statusMessage = 'Rendering WAV export...');
    try {
      final samples = previewMode == 'Enhanced'
          ? report.enhancedSamples
          : report.mixSamples;
      if (samples.isEmpty) {
        setState(
          () => statusMessage =
              'WAV export needs a live analysis. Import WAV files or run the demo first.',
        );
        return;
      }
      final bytes = WavEncoder().encodeMono16(
        samples: samples,
        sampleRate: report.sampleRate,
      );
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export Auralyze WAV',
        fileName:
            '${_safeFileBase(projectName)}-${previewMode.toLowerCase()}-auralyze.wav',
        type: FileType.custom,
        allowedExtensions: const ['wav'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'WAV export cancelled'
            : 'WAV exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'WAV export failed: $error');
    }
  }

  Future<void> playSelectedPreview() async {
    final samples = previewMode == 'Enhanced'
        ? report.enhancedSamples
        : report.mixSamples;
    if (samples.isEmpty) {
      setState(
        () => statusMessage =
            'Playback needs a live analysis. Import WAV files or run the demo first.',
      );
      return;
    }
    try {
      final bytes = WavEncoder().encodeMono16(
        samples: samples,
        sampleRate: report.sampleRate,
      );
      await previewPlayer.stop();
      await previewPlayer.play(BytesSource(bytes));
      setState(() {
        playingPreviewMode = previewMode;
        previewPlaying = true;
        statusMessage = 'Playing $previewMode preview';
      });
    } catch (error) {
      setState(() => statusMessage = 'Playback failed: $error');
    }
  }

  List<double> _renderRepairSamples() {
    return analyzer.renderRepairPreview(
      report.mixSamples,
      report.sampleRate,
      report.metrics,
    );
  }

  Future<void> playRepairedPreview() async {
    if (report.mixSamples.isEmpty) {
      setState(() => statusMessage = 'Repair playback needs live audio first');
      return;
    }
    try {
      final bytes = WavEncoder().encodeMono16(
        samples: _renderRepairSamples(),
        sampleRate: report.sampleRate,
      );
      await previewPlayer.stop();
      await previewPlayer.play(BytesSource(bytes));
      setState(() {
        playingPreviewMode = 'Repaired';
        previewPlaying = true;
        statusMessage = 'Playing repaired preview';
      });
    } catch (error) {
      setState(() => statusMessage = 'Repair playback failed: $error');
    }
  }

  Future<void> exportRepairedWav() async {
    if (report.mixSamples.isEmpty) {
      setState(() => statusMessage = 'Repair export needs live audio first');
      return;
    }
    try {
      final bytes = WavEncoder().encodeMono16(
        samples: _renderRepairSamples(),
        sampleRate: report.sampleRate,
      );
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export repaired WAV',
        fileName: '${_safeFileBase(projectName)}-repaired-auralyze.wav',
        type: FileType.custom,
        allowedExtensions: const ['wav'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'Repair export cancelled'
            : 'Repaired WAV exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'Repair export failed: $error');
    }
  }

  Future<void> stopPreview() async {
    await previewPlayer.stop();
    setState(() {
      previewPlaying = false;
      playingPreviewMode = '';
      statusMessage = 'Preview stopped';
    });
  }

  Future<void> refreshSystemStatus() async {
    setState(() => checkingSystem = true);
    var nextBackendStatus = 'Offline';
    var nextAiStatus = 'Unknown';
    var nextRagStatus = 'Unknown';
    var nextFormatStatus = 'Unknown';
    var nextSeparationStatus = 'Unknown';
    var nextAuthStatus = 'Unknown';
    var nextBillingStatus = 'Unknown';
    var nextStorageStatus = 'Unknown';
    try {
      final health = await http
          .get(Uri.parse('$backendBaseUrl/health'))
          .timeout(const Duration(seconds: 4));
      nextBackendStatus = health.statusCode == 200
          ? 'Online'
          : 'HTTP ${health.statusCode}';

      final ai = await http
          .get(Uri.parse('$backendBaseUrl/api/ai/status'))
          .timeout(const Duration(seconds: 4));
      if (ai.statusCode == 200) {
        final payload = jsonDecode(ai.body) as Map<String, dynamic>;
        final mode = payload['mode'] as String? ?? 'local-rag-rules';
        final model = payload['model'] as String? ?? 'local';
        if (mode == 'local-llm-ready') {
          nextAiStatus = 'Free local LLM ready ($model)';
        } else if (mode == 'ollama-model-missing') {
          nextAiStatus = 'Ollama running - pull $model';
        } else if (mode == 'openai-ready') {
          nextAiStatus = 'OpenAI ready ($model)';
        } else if (mode == 'openai-missing-key') {
          nextAiStatus = 'OpenAI selected - key missing';
        } else {
          nextAiStatus = 'Free local DSP/OKF rules';
        }
      } else {
        nextAiStatus = 'HTTP ${ai.statusCode}';
      }

      final auth = await http
          .get(Uri.parse('$backendBaseUrl/api/auth/status'))
          .timeout(const Duration(seconds: 4));
      if (auth.statusCode == 200) {
        final payload = jsonDecode(auth.body) as Map<String, dynamic>;
        final provider = payload['provider'] as String? ?? 'local';
        final configured = payload['configured'] == true;
        final required = payload['requireAuth'] == true;
        if (provider == 'local') {
          nextAuthStatus = required ? 'Local auth required' : 'Local demo auth';
        } else if (configured) {
          nextAuthStatus = '$provider ready${required ? '' : ' optional'}';
        } else {
          nextAuthStatus = '$provider selected - config missing';
        }
      } else {
        nextAuthStatus = 'HTTP ${auth.statusCode}';
      }

      final docs = await http
          .get(Uri.parse('$backendBaseUrl/api/knowledge/documents'))
          .timeout(const Duration(seconds: 4));
      if (docs.statusCode == 200) {
        final payload = jsonDecode(docs.body) as Map<String, dynamic>;
        final documents = payload['documents'] as List<dynamic>? ?? [];
        final chunks = documents.fold<int>(
          0,
          (total, doc) =>
              total +
              ((doc is Map<String, dynamic> && doc['chunkCount'] is num)
                  ? (doc['chunkCount'] as num).round()
                  : 0),
        );
        nextRagStatus = '${documents.length} docs, $chunks chunks';
      } else {
        nextRagStatus = 'HTTP ${docs.statusCode}';
      }

      final audio = await http
          .get(Uri.parse('$backendBaseUrl/api/audio/status'))
          .timeout(const Duration(seconds: 4));
      if (audio.statusCode == 200) {
        final payload = jsonDecode(audio.body) as Map<String, dynamic>;
        nextFormatStatus = payload['ffmpegAvailable'] == true
            ? 'WAV + MP3/M4A/FLAC via FFmpeg'
            : 'WAV only - install FFmpeg';
      } else {
        nextFormatStatus = 'HTTP ${audio.statusCode}';
      }

      final separation = await http
          .get(Uri.parse('$backendBaseUrl/api/stem-separation/status'))
          .timeout(const Duration(seconds: 4));
      if (separation.statusCode == 200) {
        final payload = jsonDecode(separation.body) as Map<String, dynamic>;
        if (payload['available'] == true) {
          final mode = payload['mode'] as String? ?? 'demucs';
          if (mode == 'ffmpeg-fallback') {
            nextSeparationStatus = 'FFmpeg fallback ready';
          } else {
            nextSeparationStatus = payload['ffmpegAvailable'] == true
                ? 'Demucs ready'
                : 'Demucs ready - WAV only';
          }
        } else {
          nextSeparationStatus = 'Install FFmpeg or Demucs';
        }
      } else {
        nextSeparationStatus = 'HTTP ${separation.statusCode}';
      }

      final billing = await http
          .get(Uri.parse('$backendBaseUrl/api/billing/status'))
          .timeout(const Duration(seconds: 4));
      if (billing.statusCode == 200) {
        final payload = jsonDecode(billing.body) as Map<String, dynamic>;
        nextBillingStatus = payload['stripeConfigured'] == true
            ? 'External checkout ready'
            : 'Free local plans';
      } else {
        nextBillingStatus = 'HTTP ${billing.statusCode}';
      }

      final storage = await http
          .get(Uri.parse('$backendBaseUrl/api/storage/status'))
          .timeout(const Duration(seconds: 4));
      if (storage.statusCode == 200) {
        final payload = jsonDecode(storage.body) as Map<String, dynamic>;
        final backend = payload['backend'] as String? ?? 'json';
        final projectCount = (payload['projectCount'] as num?)?.round() ?? 0;
        final knowledgeCount =
            (payload['knowledgeDocumentCount'] as num?)?.round() ?? 0;
        nextStorageStatus =
            '$backend, $projectCount projects, $knowledgeCount custom docs';
      } else {
        nextStorageStatus = 'HTTP ${storage.statusCode}';
      }
    } catch (error) {
      nextBackendStatus = 'Offline - start backend';
      nextAiStatus = 'Unavailable';
      nextRagStatus = 'Unavailable';
      nextFormatStatus = 'Unavailable';
      nextSeparationStatus = 'Unavailable';
      nextAuthStatus = 'Unavailable';
      nextBillingStatus = 'Unavailable';
      nextStorageStatus = 'Unavailable';
    }
    if (!mounted) return;
    setState(() {
      backendStatus = nextBackendStatus;
      aiStatus = nextAiStatus;
      ragStatus = nextRagStatus;
      formatStatus = nextFormatStatus;
      separationStatus = nextSeparationStatus;
      authStatus = nextAuthStatus;
      billingStatus = nextBillingStatus;
      storageStatus = nextStorageStatus;
      checkingSystem = false;
    });
  }

  Future<void> exportHtmlReport() async {
    setState(() => statusMessage = 'Creating HTML report...');
    try {
      final bytes = ReportExporter().htmlReportBytes(report);
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export Auralyze HTML report',
        fileName: '${_safeFileBase(projectName)}-auralyze-report.html',
        type: FileType.custom,
        allowedExtensions: const ['html'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'HTML report export cancelled'
            : 'HTML report exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'HTML report export failed: $error');
    }
  }

  Future<void> exportProjectJson() async {
    setState(() => statusMessage = 'Creating project JSON...');
    try {
      final bytes = ReportExporter().jsonReportBytes(report);
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export Auralyze project',
        fileName: '${_safeFileBase(projectName)}.auralyze.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'Project export cancelled'
            : 'Project JSON exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'Project export failed: $error');
    }
  }

  Future<void> loginLocalAccount() async {
    final email = accountEmailController.text.trim().isEmpty
        ? 'local@auralyze.dev'
        : accountEmailController.text.trim();
    setState(() {
      accountStatus = 'Signing in...';
      statusMessage = 'Signing in locally';
    });
    try {
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/accounts/local-login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final account = payload['account'] as Map<String, dynamic>? ?? {};
      setState(() {
        accountStatus =
            'Signed in as ${account['email'] ?? email} (${account['plan'] ?? 'local'})';
        statusMessage = 'Local account ready';
      });
      await refreshCloudProjects();
    } catch (error) {
      setState(() {
        accountStatus = 'Sign-in failed';
        statusMessage = 'Local sign-in failed: $error';
      });
    }
  }

  Future<void> activateLocalPlan(String plan) async {
    final email = accountEmailController.text.trim().isEmpty
        ? 'local@auralyze.dev'
        : accountEmailController.text.trim();
    setState(() {
      billingStatus = 'Activating $plan...';
      statusMessage = 'Updating billing plan';
    });
    try {
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/billing/checkout'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'email': email, 'plan': plan}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final account = payload['account'] as Map<String, dynamic>? ?? {};
      setState(() {
        billingStatus =
            '${account['plan'] ?? plan} active (${payload['mode'] ?? 'local'})';
        accountStatus =
            'Signed in as ${account['email'] ?? email} (${account['plan'] ?? plan})';
        statusMessage = 'Plan activated';
      });
    } catch (error) {
      setState(() {
        billingStatus = 'Billing update failed';
        statusMessage = 'Billing update failed: $error';
      });
    }
  }

  Future<void> refreshCloudProjects() async {
    setState(() => cloudProjectStatus = 'Loading projects...');
    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/api/projects'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final projects =
          (payload['projects'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(CloudProject.fromJson)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        cloudProjects = projects;
        cloudProjectStatus =
            '${projects.length} saved project${projects.length == 1 ? '' : 's'}';
      });
    } catch (error) {
      setState(() => cloudProjectStatus = 'Project load failed: $error');
    }
  }

  Future<void> saveCloudProject() async {
    setState(() {
      cloudProjectStatus = 'Saving $projectName...';
      statusMessage = 'Saving cloud project';
    });
    try {
      final reportJson =
          jsonDecode(utf8.decode(ReportExporter().jsonReportBytes(report)))
              as Map<String, dynamic>;
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/projects'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'name': projectName,
              'email': accountEmailController.text.trim(),
              'releaseTarget': report.releaseTarget,
              'report': reportJson,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: ${response.body}');
      }
      setState(() {
        cloudProjectStatus = 'Saved $projectName';
        statusMessage = 'Cloud project saved';
      });
      await refreshCloudProjects();
    } catch (error) {
      setState(() {
        cloudProjectStatus = 'Save failed: $error';
        statusMessage = 'Cloud save failed';
      });
    }
  }

  Future<void> loadCloudProject(String id) async {
    setState(() {
      cloudProjectStatus = 'Loading project...';
      statusMessage = 'Loading cloud project';
    });
    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/api/projects/$id'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: ${response.body}');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final project = payload['project'] as Map<String, dynamic>? ?? {};
      final reportMap = project['report'] as Map<String, dynamic>? ?? {};
      final importedReport = ReportExporter().reportFromJsonBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(reportMap))),
      );
      setState(() {
        report = importedReport;
        currentImportedFiles = [];
        _refreshReferenceComparison();
        projectName = project['name'] as String? ?? importedReport.fileName;
        releaseTarget = importedReport.releaseTarget;
        analyzed = true;
        cloudProjectStatus = 'Loaded $projectName';
        statusMessage = 'Cloud project loaded';
      });
    } catch (error) {
      setState(() {
        cloudProjectStatus = 'Load failed: $error';
        statusMessage = 'Cloud load failed';
      });
    }
  }

  Future<void> deleteCloudProject(String id) async {
    setState(() => cloudProjectStatus = 'Deleting project...');
    try {
      final response = await http
          .delete(Uri.parse('$backendBaseUrl/api/projects/$id'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}: ${response.body}');
      }
      setState(() {
        cloudProjectStatus = 'Project deleted';
        statusMessage = 'Cloud project deleted';
      });
      await refreshCloudProjects();
    } catch (error) {
      setState(() => cloudProjectStatus = 'Delete failed: $error');
    }
  }

  Future<void> exportPresetJson() async {
    setState(() => statusMessage = 'Creating processing preset...');
    try {
      final bytes = ReportExporter().presetJsonBytes(report);
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export Auralyze processing preset',
        fileName: '${_safeFileBase(projectName)}-auralyze-preset.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'Preset export cancelled'
            : 'Processing preset exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'Preset export failed: $error');
    }
  }

  Future<void> exportReaperScript() async {
    setState(() => statusMessage = 'Creating REAPER script...');
    try {
      final bytes = ReportExporter().reaperScriptBytes(report);
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export REAPER ReaScript',
        fileName: '${_safeFileBase(projectName)}-auralyze-chain.lua',
        type: FileType.custom,
        allowedExtensions: const ['lua'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'REAPER script export cancelled'
            : 'REAPER script exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'REAPER script export failed: $error');
    }
  }

  Future<void> importProjectJson() async {
    setState(() => statusMessage = 'Opening project JSON...');
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => statusMessage = 'Project import cancelled');
        return;
      }
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Could not read project file.');
      }
      final importedReport = ReportExporter().reportFromJsonBytes(bytes);
      setState(() {
        report = importedReport;
        currentImportedFiles = importedReport.mixSamples.isEmpty
            ? []
            : [
                engine.ImportedAudio(
                  name: importedReport.fileName,
                  sampleRate: importedReport.sampleRate,
                  samples: importedReport.mixSamples,
                ),
              ];
        _refreshReferenceComparison();
        projectName = importedReport.fileName;
        releaseTarget = importedReport.releaseTarget;
        statusMessage = 'Project JSON imported';
        analyzed = true;
        copilotAnswer =
            'Project loaded. I can explain the saved diagnosis or suggest the first fix.';
        soundDesignerAnswer =
            'Imported project ready. Describe a tone change to generate a new chain.';
      });
    } catch (error) {
      setState(() => statusMessage = 'Project import failed: $error');
    }
  }

  Future<void> copyProcessingChain() async {
    final chain = report.fixes.indexed
        .map((entry) => '${entry.$1 + 1}. ${entry.$2.name}: ${entry.$2.detail}')
        .join('\n');
    await Clipboard.setData(
      ClipboardData(text: 'Auralyze chain for ${report.fileName}\n$chain'),
    );
    setState(() => statusMessage = 'Processing chain copied');
  }

  void setPreviewMode(String value) {
    setState(() {
      previewMode = value;
      statusMessage = '$value preview selected';
    });
  }

  void designSound(String prompt) {
    final query = prompt.trim().toLowerCase();
    String chain;
    if (query.contains('dark') || query.contains('cinematic')) {
      chain =
          'Chain: low-pass ambience return, broad 250 Hz control, 2.5 s hall reverb, subtle tape saturation, automate width wider in hooks.';
    } else if (query.contains('cyber') || query.contains('future')) {
      chain =
          'Chain: metallic short delay, bit-crushed parallel layer, 4 kHz motion EQ, gated reverb, tempo-synced filter automation.';
    } else if (query.contains('warm') || query.contains('analog')) {
      chain =
          'Chain: input trim, gentle tape saturation, 120 Hz body lift, smooth 8 kHz shelf, slow bus compression.';
    } else if (query.contains('vocal') || query.contains('voice')) {
      chain =
          'Chain: high-pass, dynamic mud cut, presence lift, fast de-esser, plate reverb, level automation before compression.';
    } else {
      chain =
          'Chain: level-match, remove masking, add one character processor, automate contrast, then export a reference-safe preview.';
    }
    final sound = soundGenerator.generate(
      prompt.trim().isEmpty ? query : prompt,
    );
    setState(() {
      generatedSound = sound;
      soundDesignerAnswer =
          '$chain\nGenerated: ${sound.description}\nLayers: ${sound.layers.join(', ')}';
      statusMessage = 'Sound design chain and WAV sound generated';
    });
  }

  Future<void> playGeneratedSound() async {
    final sound = generatedSound;
    if (sound == null) {
      setState(() => statusMessage = 'Generate a sound first');
      return;
    }
    try {
      final bytes = WavEncoder().encodeMono16(
        samples: sound.samples,
        sampleRate: sound.sampleRate,
      );
      await previewPlayer.stop();
      await previewPlayer.play(BytesSource(bytes));
      setState(() {
        previewPlaying = true;
        playingPreviewMode = 'Generated sound';
        statusMessage = 'Playing generated sound';
      });
    } catch (error) {
      setState(() => statusMessage = 'Generated sound playback failed: $error');
    }
  }

  Future<void> exportGeneratedSound() async {
    final sound = generatedSound;
    if (sound == null) {
      setState(() => statusMessage = 'Generate a sound first');
      return;
    }
    try {
      final bytes = WavEncoder().encodeMono16(
        samples: sound.samples,
        sampleRate: sound.sampleRate,
      );
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export generated sound',
        fileName: sound.name,
        type: FileType.custom,
        allowedExtensions: const ['wav'],
        bytes: bytes,
      );
      setState(() {
        statusMessage = output == null
            ? 'Generated sound export cancelled'
            : 'Generated sound exported';
      });
    } catch (error) {
      setState(() => statusMessage = 'Generated sound export failed: $error');
    }
  }

  void updateSampleQuery(String value) {
    setState(() {
      sampleQuery = value.trim().isEmpty ? 'dark cinematic impacts' : value;
      statusMessage = 'Sample search updated';
    });
  }

  Future<void> addKnowledgeDocument() async {
    final title = knowledgeTitleController.text.trim();
    final text = knowledgeTextController.text.trim();
    if (title.isEmpty || text.isEmpty) {
      setState(() {
        knowledgeStatus = 'Add a title and reference text first.';
        statusMessage = 'Knowledge note incomplete';
      });
      return;
    }
    setState(() {
      knowledgeStatus = 'Saving knowledge note...';
      statusMessage = 'Updating OKF/RAG knowledge';
    });
    try {
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/knowledge/documents'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'tags': knowledgeTagsController.text,
              'text': text,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          knowledgeStatus =
              'Saved "${payload['document']['title']}" with ${payload['chunkCount']} chunk(s). Ask the copilot about it.';
          statusMessage = 'Knowledge note saved';
        });
        return;
      }
      throw StateError('Backend returned HTTP ${response.statusCode}');
    } catch (error) {
      setState(() {
        knowledgeStatus =
            'Could not save yet. Start backend on port 8788, then try again. $error';
        statusMessage = 'Knowledge save failed';
      });
    }
  }

  Future<void> askCopilot(String question) async {
    final query = question.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        copilotAnswer =
            'Ask about mud, vocals, kick/bass conflicts, loudness, plugins, or what to fix first.';
      });
      return;
    }

    setState(() {
      copilotAnswer = 'Thinking with the current audio report...';
      statusMessage = 'Asking AI copilot';
    });
    try {
      final reportJson =
          jsonDecode(utf8.decode(ReportExporter().jsonReportBytes(report)))
              as Map<String, dynamic>;
      final comparison = referenceComparison;
      if (comparison != null) {
        reportJson['referenceMatch'] = {
          'referenceName': comparison.referenceName,
          'matchScore': comparison.matchScore,
          'loudnessDelta': comparison.loudnessDelta,
          'crestDelta': comparison.crestDelta,
          'truePeakDelta': comparison.truePeakDelta,
          'findings': comparison.findings.map((finding) {
            return {
              'severity': finding.severity.name,
              'title': finding.title,
              'detail': finding.detail,
              'action': finding.action,
              'delta': finding.delta,
            };
          }).toList(),
        };
      }
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/copilot'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'question': question, 'report': reportJson}),
          )
          .timeout(const Duration(seconds: 120));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final rawMode = payload['mode'] as String? ?? 'local-rules';
        var mode = 'Local DSP/OKF';
        if (rawMode == 'ollama') {
          mode = 'Free local LLM';
        } else if (rawMode == 'openai') {
          mode = 'OpenAI';
        }
        final model = payload['model'] == null ? '' : ' (${payload['model']})';
        final error = payload['error'] == null
            ? ''
            : '\n\nFallback note: ${payload['error']}';
        setState(() {
          copilotAnswer = '$mode$model: ${payload['answer']}$error';
          statusMessage = rawMode == 'ollama'
              ? 'Free local model answered'
              : rawMode == 'openai'
              ? 'OpenAI copilot answered'
              : 'Local copilot answered';
        });
        return;
      }
      throw StateError('Backend returned HTTP ${response.statusCode}');
    } catch (error) {
      setState(() {
        copilotAnswer =
            '${_localCopilotAnswer(query)}\n\nLocal fallback: $error';
        statusMessage = 'Copilot fallback used';
      });
      return;
    }
  }

  String _localCopilotAnswer(String query) {
    final issue = report.issues.where((item) {
      final haystack = '${item.title} ${item.evidence} ${item.fix}'
          .toLowerCase();
      return query
          .split(RegExp(r'\s+'))
          .any((word) => word.length > 3 && haystack.contains(word));
    }).firstOrNull;

    String answer;
    if (query.contains('first') || query.contains('start')) {
      final first = report.fixes.first;
      answer =
          'Start with ${first.name.toLowerCase()}: ${first.detail} Then re-check peak, mud, and masking before mastering.';
    } else if (query.contains('reference') ||
        query.contains('compare') ||
        query.contains('match')) {
      final comparison = referenceComparison;
      if (comparison == null) {
        answer =
            'Choose a reference audio file first. I will compare loudness, dynamics, peak headroom, and tonal balance against the current mix.';
      } else {
        final first = comparison.findings.first;
        answer =
            'Reference score is ${comparison.matchScore.round()}% against ${comparison.referenceName}. Biggest move: ${first.title}. ${first.action}';
      }
    } else if (query.contains('vocal') || query.contains('voice')) {
      answer =
          'For vocals, set level first, carve 2-4 kHz space in competing stems, compress gently, then de-ess only if harshness remains.';
    } else if (query.contains('mud') || query.contains('muddy')) {
      answer =
          'The usual mud zone is 150-350 Hz. Cut broad low-mid buildup on non-lead parts before boosting presence.';
    } else if (query.contains('kick') ||
        query.contains('bass') ||
        query.contains('808')) {
      answer =
          'Pick one owner for 50-80 Hz, then sidechain or dynamic-EQ the other part so the groove keeps impact without low-end blur.';
    } else if (query.contains('plugin') || query.contains('tool')) {
      final plugin = report.plugins.first;
      answer =
          'Use a ${plugin.name.toLowerCase()} first. Reason: ${plugin.reason}';
    } else if (issue != null) {
      answer = '${issue.title}: ${issue.fix} Evidence: ${issue.evidence}';
    } else {
      answer =
          'Level-match first, fix the strongest diagnosis item, then export a new preview and compare translation on the ${report.releaseTarget} target.';
    }

    return answer;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        contentType: contentType,
                        releaseTarget: releaseTarget,
                        statusMessage: statusMessage,
                        onContentChanged: (value) =>
                            setState(() => contentType = value),
                        onTargetChanged: applyReleaseTarget,
                        onRunDemo: runDemoAnalysis,
                        onExportWav: exportCurrentWav,
                        onExportHtml: exportHtmlReport,
                      ),
                      const SizedBox(height: 18),
                      wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 350,
                                  child: _LeftRail(state: this),
                                ),
                                const SizedBox(width: 18),
                                Expanded(child: _MainStage(state: this)),
                              ],
                            )
                          : Column(
                              children: [
                                _LeftRail(state: this),
                                const SizedBox(height: 18),
                                _MainStage(state: this),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.contentType,
    required this.releaseTarget,
    required this.statusMessage,
    required this.onContentChanged,
    required this.onTargetChanged,
    required this.onRunDemo,
    required this.onExportWav,
    required this.onExportHtml,
  });

  final String contentType;
  final String releaseTarget;
  final String statusMessage;
  final ValueChanged<String> onContentChanged;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onRunDemo;
  final VoidCallback onExportWav;
  final VoidCallback onExportHtml;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI AUDIO DIAGNOSIS COPILOT',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF075B57),
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'Auralyze',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              statusMessage,
              style: const TextStyle(color: Color(0xFF65706E)),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Menu(
              value: contentType,
              values: const [
                'Music mix',
                'Podcast / voice',
                'Film / video',
                'General audio',
              ],
              onChanged: onContentChanged,
            ),
            _Menu(
              value: releaseTarget,
              values: const [
                'Balanced',
                'Streaming',
                'YouTube',
                'Club',
                'Cinema',
                'Podcast',
              ],
              onChanged: onTargetChanged,
            ),
            FilledButton.icon(
              onPressed: onRunDemo,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Run demo analysis'),
            ),
            FilledButton.icon(
              onPressed: onExportWav,
              icon: const Icon(Icons.graphic_eq),
              label: const Text('Export WAV'),
            ),
            OutlinedButton.icon(
              onPressed: onExportHtml,
              icon: const Icon(Icons.description),
              label: const Text('HTML report'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LeftRail extends StatelessWidget {
  const _LeftRail({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SystemStatusPanel(state: state),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Drop in audio',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              const Text(
                'Use WAV directly, or MP3, M4A, AAC, FLAC, and OGG when the backend has FFmpeg.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.analyzingFiles
                    ? null
                    : state.chooseAndAnalyzeFiles,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  state.analyzingFiles ? 'Analyzing...' : 'Choose audio files',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: state.separatingStems
                    ? null
                    : state.chooseAndSeparateSong,
                icon: const Icon(Icons.call_split),
                label: Text(
                  state.separatingStems ? 'Separating...' : 'Separate one song',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Uses Demucs when installed, otherwise a free FFmpeg spectral fallback on hosted demos.',
                style: TextStyle(color: Color(0xFF65706E)),
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Kicker('Reference match'),
              const Text(
                'Upload a finished song or master to compare loudness, tone, and dynamics.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: state.analyzingReference
                    ? null
                    : state.chooseReferenceFile,
                icon: const Icon(Icons.compare_arrows),
                label: Text(
                  state.analyzingReference ? 'Matching...' : 'Choose reference',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                state.referenceComparison == null
                    ? 'No reference loaded'
                    : state.referenceComparison!.referenceName,
                style: const TextStyle(color: Color(0xFF65706E)),
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Kicker('Projects'),
              TextField(
                controller: TextEditingController(text: state.projectName),
                decoration: const InputDecoration(
                  labelText: 'Project name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => state.projectName = value,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: state.accountEmailController,
                decoration: const InputDecoration(
                  labelText: 'Account email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: state.loginLocalAccount,
                      child: const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => state.activateLocalPlan('pro'),
                      child: const Text('Activate Local Pro'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                state.accountStatus,
                style: const TextStyle(color: Color(0xFF65706E)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: state.saveCloudProject,
                      child: const Text('Cloud save'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.refreshCloudProjects,
                      child: const Text('Refresh'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                state.cloudProjectStatus,
                style: const TextStyle(color: Color(0xFF65706E)),
              ),
              const SizedBox(height: 8),
              ...state.cloudProjects
                  .take(4)
                  .map((project) => _CloudProjectRow(project, state)),
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.exportProjectJson,
                      child: const Text('File export'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.importProjectJson,
                      child: const Text('File import'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _MetricsCard(metrics: state.report.metrics),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Kicker('Stem intelligence'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Track roles',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  _Pill('${state.stems.length} stems'),
                ],
              ),
              const SizedBox(height: 12),
              ...state.stems.map((stem) => _StemRow(stem)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SystemStatusPanel extends StatelessWidget {
  const _SystemStatusPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'System status',
            'Real service checks',
            state.checkingSystem ? 'Checking' : 'Live',
          ),
          _InfoRow('Backend', state.backendStatus),
          _InfoRow('AI copilot', state.aiStatus),
          _InfoRow('OKF/RAG knowledge', state.ragStatus),
          _InfoRow('Formats', state.formatStatus),
          _InfoRow('Stem separation', state.separationStatus),
          _InfoRow('Auth', state.authStatus),
          _InfoRow('Storage', state.storageStatus),
          _InfoRow('Billing', state.billingStatus),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: state.checkingSystem ? null : state.refreshSystemStatus,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh status'),
          ),
        ],
      ),
    );
  }
}

class _CloudProjectRow extends StatelessWidget {
  const _CloudProjectRow(this.project, this.state);

  final CloudProject project;
  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9DDD5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _Pill(project.releaseTarget)),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Load',
                onPressed: () => state.loadCloudProject(project.id),
                icon: const Icon(Icons.download),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => state.deleteCloudProject(project.id),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MainStage extends StatelessWidget {
  const _MainStage({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Panel(child: _EvidenceCanvas(report: state.report)),
        _PreviewPanel(state: state),
        _ReferencePanel(state: state),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                'Timeline triage',
                'Problem moments',
                '${state.markers.length} markers',
              ),
              ...state.markers.map((marker) => _TimelineRow(marker)),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth > 760;
            final diagnosis = _DiagnosisPanel(issues: state.issues);
            final chain = _ProcessingPanel(report: state.report);
            if (!twoColumns) {
              return Column(
                children: [diagnosis, const SizedBox(height: 14), chain],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: diagnosis),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: chain),
              ],
            );
          },
        ),
        _CopilotPanel(state: state),
        _KnowledgePanel(state: state),
        _SoundDesignerPanel(state: state),
        _PluginPanel(plugins: state.report.plugins),
        _MasteringPanel(state: state),
        _ArrangementPanel(suggestions: state.arrangementSuggestions),
        _RepairPanel(state: state),
        _SampleSearchPanel(state: state),
        _IntegrationPanel(),
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    final hasLiveAudio = state.report.mixSamples.isNotEmpty;
    final enhancedMetrics = hasLiveAudio
        ? state.analyzer.analyzeMetrics(
            state.report.enhancedSamples,
            state.report.sampleRate,
          )
        : state.report.metrics;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'A/B preview',
            'Original vs enhanced',
            state.previewMode,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Original'),
                selected: state.previewMode == 'Original',
                onSelected: (_) => state.setPreviewMode('Original'),
              ),
              ChoiceChip(
                label: const Text('Enhanced'),
                selected: state.previewMode == 'Enhanced',
                onSelected: (_) => state.setPreviewMode('Enhanced'),
              ),
              FilledButton.icon(
                onPressed: hasLiveAudio && !state.previewPlaying
                    ? state.playSelectedPreview
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text('Play ${state.previewMode}'),
              ),
              OutlinedButton.icon(
                onPressed: state.previewPlaying ? state.stopPreview : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
              FilledButton.icon(
                onPressed: hasLiveAudio ? state.exportCurrentWav : null,
                icon: const Icon(Icons.download),
                label: const Text('Export selected WAV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            'Original peak',
            '${state.report.metrics.peakDb.toStringAsFixed(1)} dBFS',
          ),
          _InfoRow(
            'Enhanced peak',
            '${enhancedMetrics.peakDb.toStringAsFixed(1)} dBFS',
          ),
          _InfoRow(
            'Playback',
            state.previewPlaying
                ? 'Playing ${state.playingPreviewMode}'
                : 'Stopped',
          ),
          _InfoRow(
            'Preview chain',
            hasLiveAudio
                ? 'High-pass rumble cleanup, adaptive mud/clarity EQ, compressor, de-esser, saturation, true-peak limiter'
                : 'Run demo or import WAV files to render audio',
          ),
        ],
      ),
    );
  }
}

class _ReferencePanel extends StatelessWidget {
  const _ReferencePanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    final comparison = state.referenceComparison;
    if (comparison == null) {
      return _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              'Reference match',
              'Compare against a finished track',
              'Waiting',
            ),
            const Text(
              'Choose a reference file to reveal loudness, dynamics, true-peak, and tonal-balance gaps against the current mix.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: state.analyzingReference
                  ? null
                  : state.chooseReferenceFile,
              icon: const Icon(Icons.compare),
              label: Text(
                state.analyzingReference
                    ? 'Matching...'
                    : 'Choose reference audio',
              ),
            ),
          ],
        ),
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Reference match',
            comparison.referenceName,
            '${comparison.matchScore.round()}% close',
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 760 ? 4 : 2;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: columns == 4 ? 2.2 : 2.5,
                children: [
                  _ReferenceMetricTile(
                    label: 'Match',
                    value: '${comparison.matchScore.round()}%',
                    detail: _matchLabel(comparison.matchScore),
                  ),
                  _ReferenceMetricTile(
                    label: 'Loudness',
                    value: _signed(comparison.loudnessDelta, 'LUFS'),
                    detail: 'mix vs reference',
                  ),
                  _ReferenceMetricTile(
                    label: 'Dynamics',
                    value: _signed(comparison.crestDelta, 'dB'),
                    detail: 'crest factor',
                  ),
                  _ReferenceMetricTile(
                    label: 'True peak',
                    value: _signed(comparison.truePeakDelta, 'dB'),
                    detail: 'headroom delta',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          ...comparison.findings.map(
            (finding) => _ReferenceFindingCard(finding),
          ),
        ],
      ),
    );
  }

  String _matchLabel(double score) {
    if (score >= 86) return 'translation-ready';
    if (score >= 70) return 'small moves';
    if (score >= 52) return 'needs matching';
    return 'major gaps';
  }

  String _signed(double value, String unit) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} $unit';
  }
}

class _ReferenceMetricTile extends StatelessWidget {
  const _ReferenceMetricTile({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9DDD5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF65706E),
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            Text(detail, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ReferenceFindingCard extends StatelessWidget {
  const _ReferenceFindingCard(this.finding);

  final engine.ReferenceFinding finding;

  @override
  Widget build(BuildContext context) {
    final severity = Severity.fromEngine(finding.severity);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: severity.color, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            finding.title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            finding.detail,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('Move: ${finding.action}'),
        ],
      ),
    );
  }
}

class _SoundDesignerPanel extends StatelessWidget {
  const _SoundDesignerPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'AI sound designer',
            'Prompt to processing chain',
            'Local',
          ),
          TextField(
            controller: state.soundDesignerController,
            onSubmitted: state.designSound,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText:
                  'Make this guitar darker, warmer, cinematic, cyberpunk...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.auto_awesome),
                onPressed: () =>
                    state.designSound(state.soundDesignerController.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(state.soundDesignerAnswer),
          const SizedBox(height: 12),
          if (state.generatedSound != null) ...[
            CustomPaint(
              size: const Size(double.infinity, 92),
              painter: WavePainter(
                state.analyzer.downsample(state.generatedSound!.samples, 140),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: state.generatedSound == null
                    ? null
                    : state.playGeneratedSound,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play generated'),
              ),
              OutlinedButton.icon(
                onPressed: state.generatedSound == null
                    ? null
                    : state.exportGeneratedSound,
                icon: const Icon(Icons.download),
                label: const Text('Export WAV'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KnowledgePanel extends StatelessWidget {
  const _KnowledgePanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'OKF/RAG knowledge',
            'Add a production reference',
            'Retrieval on',
          ),
          TextField(
            controller: state.knowledgeTitleController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Reference title',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: state.knowledgeTagsController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Tags',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: state.knowledgeTextController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Reference text',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: state.addKnowledgeDocument,
            icon: const Icon(Icons.library_add),
            label: const Text('Add to copilot knowledge'),
          ),
          const SizedBox(height: 12),
          Text(state.knowledgeStatus),
        ],
      ),
    );
  }
}

class _MasteringPanel extends StatelessWidget {
  const _MasteringPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    final exports = state.masteringExports;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Mastering assistant',
            'Release versions',
            '${exports.length} targets',
          ),
          ...exports.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD6D3C8)),
                  borderRadius: BorderRadius.circular(8),
                  color: item.name == _masteringNameFor(state.releaseTarget)
                      ? const Color(0xFFE8F3EF)
                      : Colors.white,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.loudness}, ${item.truePeak} - ${item.note}',
                              style: const TextStyle(color: Color(0xFF4F5D5B)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      item.name == _masteringNameFor(state.releaseTarget)
                          ? FilledButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.check),
                              label: const Text('Active'),
                            )
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  state.applyMasteringTarget(item.name),
                              icon: const Icon(Icons.tune),
                              label: const Text('Apply'),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'Applied targets rerender the enhanced preview. Use Export selected WAV to save the active version.',
            style: TextStyle(color: Color(0xFF65706E)),
          ),
        ],
      ),
    );
  }

  String _masteringNameFor(String target) {
    const names = {
      'Streaming': 'Spotify',
      'YouTube': 'YouTube',
      'Club': 'Club',
      'Podcast': 'Podcast',
      'Cinema': 'Cinema',
    };
    return names[target] ?? '';
  }
}

class _ArrangementPanel extends StatelessWidget {
  const _ArrangementPanel({required this.suggestions});

  final List<engine.ArrangementSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Arrangement assistant',
            'Energy and automation',
            '${suggestions.length} moves',
          ),
          ...suggestions.map((item) => _InfoRow(item.title, item.detail)),
        ],
      ),
    );
  }
}

class _RepairPanel extends StatelessWidget {
  const _RepairPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    final actions = state.repairActions;
    final hasAudio = state.report.mixSamples.isNotEmpty;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Audio repair',
            'Restoration checklist',
            '${actions.length} scans',
          ),
          ...actions.map(
            (action) =>
                _InfoRow('${action.name} (${action.status})', action.detail),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: hasAudio ? state.playRepairedPreview : null,
                icon: const Icon(Icons.healing),
                label: const Text('Play repaired'),
              ),
              OutlinedButton.icon(
                onPressed: hasAudio ? state.exportRepairedWav : null,
                icon: const Icon(Icons.download),
                label: const Text('Export repaired WAV'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SampleSearchPanel extends StatelessWidget {
  const _SampleSearchPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Intelligent sample search',
            'Semantic matches',
            '${state.sampleMatches.length} hits',
          ),
          TextField(
            controller: state.sampleSearchController,
            onSubmitted: state.updateSampleQuery,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText:
                  'dark cinematic impacts, warm snare, cyberpunk ambience...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () =>
                    state.updateSampleQuery(state.sampleSearchController.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...state.sampleMatches.map(
            (sample) => _InfoRow(
              sample.name,
              '${sample.tags.join(', ')} - ${sample.note}',
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrationPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Production integrations',
            'Backend-ready feature surface',
            '8 groups',
          ),
          _InfoRow(
            'Open-source copilot',
            'Uses Ollama when a local model is running, otherwise falls back to local DSP/OKF rules.',
          ),
          _InfoRow(
            'OKF/RAG knowledge',
            'Structured OKF files, markdown notes, and saved references are searched locally without a vector database.',
          ),
          _InfoRow(
            'Accounts and cloud projects',
            'Local account and project API saves, loads, and deletes analysis snapshots.',
          ),
          _InfoRow(
            'Stem separation',
            'Demucs separates songs when installed; hosted demos use a free FFmpeg spectral fallback.',
          ),
          _InfoRow(
            'Formats',
            'WAV works in-app; MP3/M4A/AAC/FLAC/OGG use FFmpeg through the backend.',
          ),
          _InfoRow(
            'DAW/plugin automation',
            'Processing chains are copyable and exportable; REAPER/VST preset writers can attach here.',
          ),
        ],
      ),
    );
  }
}

class _EvidenceCanvas extends StatelessWidget {
  const _EvidenceCanvas({required this.report});

  final engine.AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          'Evidence',
          'Waveform and spectrum',
          'Analysis complete',
        ),
        const SizedBox(height: 8),
        CustomPaint(
          size: const Size(double.infinity, 210),
          painter: WavePainter(report.waveform),
        ),
        const SizedBox(height: 12),
        CustomPaint(
          size: const Size(double.infinity, 170),
          painter: SpectrumPainter(report.spectrum.visualSpectrum),
        ),
      ],
    );
  }
}

class _DiagnosisPanel extends StatelessWidget {
  const _DiagnosisPanel({required this.issues});

  final List<Diagnosis> issues;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Copilot diagnosis',
            'What sounds wrong?',
            '${issues.length} issues',
          ),
          const Text(
            'Auralyze found mix decisions that are likely affecting clarity, translation, and release readiness.',
          ),
          const SizedBox(height: 12),
          ...issues.map((issue) => _IssueCard(issue)),
        ],
      ),
    );
  }
}

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel({required this.report});

  final engine.AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final steps = report.fixes;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Suggested processing',
            'Enhanced preview chain',
            '${steps.length} steps',
          ),
          ...steps.indexed.map(
            (entry) => _FixStep(
              index: entry.$1 + 1,
              text: '${entry.$2.name}: ${entry.$2.detail}',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: report.fixes.isEmpty
                    ? null
                    : () => context
                          .findAncestorStateOfType<_AuralyzeHomeState>()
                          ?.copyProcessingChain(),
                icon: const Icon(Icons.copy),
                label: const Text('Copy chain'),
              ),
              FilledButton.icon(
                onPressed: report.fixes.isEmpty
                    ? null
                    : () => context
                          .findAncestorStateOfType<_AuralyzeHomeState>()
                          ?.exportPresetJson(),
                icon: const Icon(Icons.save_alt),
                label: const Text('Export preset'),
              ),
              OutlinedButton.icon(
                onPressed: report.fixes.isEmpty
                    ? null
                    : () => context
                          .findAncestorStateOfType<_AuralyzeHomeState>()
                          ?.exportReaperScript(),
                icon: const Icon(Icons.queue_music),
                label: const Text('REAPER script'),
              ),
              OutlinedButton.icon(
                onPressed: () => context
                    .findAncestorStateOfType<_AuralyzeHomeState>()
                    ?.runDemoAnalysis(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopilotPanel extends StatelessWidget {
  const _CopilotPanel({required this.state});

  final _AuralyzeHomeState state;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Ask Auralyze', 'Production copilot', 'Knowledge on'),
          TextField(
            controller: state.copilotController,
            onSubmitted: state.askCopilot,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Ask why it sounds muddy, how to fix vocals, or what to do first',
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => state.askCopilot(state.copilotController.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFBFBF8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(state.copilotAnswer),
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginPanel extends StatelessWidget {
  const _PluginPanel({required this.plugins});

  final List<engine.PluginRecommendation> plugins;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            'Plugin copilot',
            'Recommended tools',
            '${plugins.length} tools',
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 900
                  ? 4
                  : constraints.maxWidth > 520
                  ? 2
                  : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: columns == 1 ? 4.2 : 2.4,
                children: plugins.map((plugin) => _PluginCard(plugin)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.metrics});

  final engine.AnalysisMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Peak', '${metrics.peakDb.toStringAsFixed(1)} dBFS'),
      ('True peak', '${metrics.truePeakDb.toStringAsFixed(1)} dBTP'),
      ('Loudness', '${metrics.lufsApprox.toStringAsFixed(1)} LUFS*'),
      ('Noise floor', '${metrics.noiseFloorDb.toStringAsFixed(1)} dB'),
      ('Dynamics', '${metrics.crestFactor.toStringAsFixed(1)} dB'),
      ('Clipping', '${(metrics.clippedRatio * 100).toStringAsFixed(2)}%'),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Kicker('Signal metrics'),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    row.$1,
                    style: const TextStyle(color: Color(0xFF65706E)),
                  ),
                  Text(
                    row.$2,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9DDD5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17182220),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.kicker, this.title, this.pill);

  final String kicker;
  final String title;
  final String pill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Kicker(kicker),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          _Pill(pill),
        ],
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: Color(0xFF075B57),
        letterSpacing: 1.2,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD9DDD5)),
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFFBFBF8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Color(0xFF65706E),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF65706E),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard(this.issue);

  final Diagnosis issue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: issue.severity.color, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            issue.title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            issue.evidence,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('Move: ${issue.fix}'),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(this.marker);

  final TimelineMarker marker;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Pill(marker.time),
      title: Text(
        marker.title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(marker.detail),
      trailing: Icon(Icons.circle, color: marker.severity.color, size: 14),
    );
  }
}

class _StemRow extends StatelessWidget {
  const _StemRow(this.stem);

  final StemTrack stem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stem.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _Pill(stem.role),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Meter(stem.low),
              _Meter(stem.body),
              _Meter(stem.clarity),
              _Meter(stem.bright),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter(this.value);

  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 7,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF0EA),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(.04, 1),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B7A75),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

class _FixStep extends StatelessWidget {
  const _FixStep({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9DDD5)),
      ),
      child: Text(
        '$index. $text',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard(this.plugin);

  final engine.PluginRecommendation plugin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9DDD5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pill(plugin.type),
          const SizedBox(height: 8),
          Text(
            plugin.name,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(plugin.reason),
        ],
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  WavePainter(this.waveform);

  final List<double> waveform;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFE5E7DF);
    for (var x = 0.0; x < size.width; x += size.width / 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final paint = Paint()
      ..color = const Color(0xFF0B7A75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < waveform.length; i += 1) {
      final x = i / (waveform.length - 1) * size.width;
      final y = size.height / 2 - waveform[i].clamp(-1, 1) * size.height * .42;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SpectrumPainter extends CustomPainter {
  SpectrumPainter(this.spectrum);

  final List<double> spectrum;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFE5E7DF);
    for (var x = 0.0; x < size.width; x += size.width / 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final colors = [
      const Color(0xFF0B7A75),
      const Color(0xFFB7791F),
      const Color(0xFFDB5F4B),
    ];
    final bar = size.width / spectrum.length;
    for (var i = 0; i < spectrum.length; i++) {
      final height = spectrum[i].clamp(.04, 1.0) * size.height * .82;
      final paint = Paint()..color = colors[(i / 24).floor().clamp(0, 2)];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bar, size.height - height, bar - 2, height),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Diagnosis {
  Diagnosis({
    required this.severity,
    required this.title,
    required this.evidence,
    required this.fix,
  });

  factory Diagnosis.fromEngine(engine.AnalysisIssue issue) {
    return Diagnosis(
      severity: Severity.fromEngine(issue.severity),
      title: issue.title,
      evidence: issue.evidence,
      fix: issue.fix,
    );
  }

  final Severity severity;
  final String title;
  final String evidence;
  final String fix;
}

class TimelineMarker {
  TimelineMarker(this.time, this.title, this.detail, this.severity);

  factory TimelineMarker.fromEngine(engine.TimelineFinding marker) {
    return TimelineMarker(
      _formatTime(marker.startSec),
      marker.title,
      marker.detail,
      Severity.fromEngine(marker.severity),
    );
  }

  final String time;
  final String title;
  final String detail;
  final Severity severity;
}

class StemTrack {
  StemTrack(
    this.name,
    this.role,
    this.low,
    this.body,
    this.clarity,
    this.bright,
  );

  factory StemTrack.fromEngine(engine.AudioStem stem) {
    final bands = stem.spectrum.bands;
    return StemTrack(
      stem.name,
      stem.role,
      ((bands['sub'] ?? 0) + (bands['bass'] ?? 0)).clamp(.04, 1),
      ((bands['lowMid'] ?? 0) + (bands['mid'] ?? 0)).clamp(.04, 1),
      ((bands['presence'] ?? 0) * 2.4).clamp(.04, 1),
      (((bands['harsh'] ?? 0) + (bands['air'] ?? 0)) * 2.2).clamp(.04, 1),
    );
  }

  final String name;
  final String role;
  final double low;
  final double body;
  final double clarity;
  final double bright;
}

enum Severity {
  good(Color(0xFF2D7D4F)),
  warning(Color(0xFFB7791F)),
  critical(Color(0xFFDB5F4B));

  const Severity(this.color);
  final Color color;

  factory Severity.fromEngine(engine.AnalysisSeverity severity) {
    return switch (severity) {
      engine.AnalysisSeverity.good => Severity.good,
      engine.AnalysisSeverity.warning => Severity.warning,
      engine.AnalysisSeverity.critical => Severity.critical,
    };
  }
}

String _formatTime(double seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds.floor() % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

String _safeFileBase(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'\.[^.]+$'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'auralyze' : cleaned;
}

class SampleMatch {
  const SampleMatch(this.name, this.tags, this.note);

  final String name;
  final List<String> tags;
  final String note;
}

class CloudProject {
  const CloudProject({
    required this.id,
    required this.name,
    required this.releaseTarget,
    required this.updatedAt,
  });

  factory CloudProject.fromJson(Map<String, dynamic> json) {
    return CloudProject(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled project',
      releaseTarget: json['releaseTarget'] as String? ?? 'Streaming',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String releaseTarget;
  final String updatedAt;
}

List<SampleMatch> _sampleMatches(String query) {
  const catalog = [
    SampleMatch('Obsidian Impact 01', [
      'dark',
      'cinematic',
      'impact',
      'trailer',
    ], 'Layered low boom with short metallic tail.'),
    SampleMatch('Tokyo Rain Bed', [
      'rain',
      'night',
      'ambient',
      'city',
    ], 'Wide ambience with soft transient texture.'),
    SampleMatch('Neon Servo Sweep', [
      'cyberpunk',
      'future',
      'sweep',
      'synth',
    ], 'Rising modulated tone for transitions.'),
    SampleMatch('Warm Dust Snare', [
      'warm',
      'snare',
      'analog',
      'lofi',
    ], 'Rounded transient with tape-like body.'),
    SampleMatch('Sub Pressure Drop', [
      'bass',
      'sub',
      'club',
      'drop',
    ], 'Clean low-frequency fall for dance builds.'),
  ];
  final terms = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length > 2)
      .toList();
  final scored = catalog.map((sample) {
    final haystack = '${sample.name} ${sample.tags.join(' ')} ${sample.note}'
        .toLowerCase();
    final score = terms.where(haystack.contains).length;
    return (score, sample);
  }).toList()..sort((a, b) => b.$1.compareTo(a.$1));
  final matches = scored
      .where((entry) => entry.$1 > 0)
      .map((entry) => entry.$2)
      .take(3)
      .toList();
  return matches.isEmpty ? catalog.take(3).toList() : matches;
}
