const audioInput = document.querySelector("#audioFile");
const uploadPanel = document.querySelector(".upload-panel");
const referenceInput = document.querySelector("#referenceFile");
const contentType = document.querySelector("#contentType");
const releaseTarget = document.querySelector("#releaseTarget");
const projectName = document.querySelector("#projectName");
const projectLibrary = document.querySelector("#projectLibrary");
const saveProjectButton = document.querySelector("#saveProject");
const deleteProjectButton = document.querySelector("#deleteProject");
const exportProjectButton = document.querySelector("#exportProject");
const projectImport = document.querySelector("#projectImport");
const exportWavButton = document.querySelector("#exportWav");
const exportHtmlButton = document.querySelector("#exportHtml");
const exportReportButton = document.querySelector("#exportReport");
const fileName = document.querySelector("#fileName");
const playOriginalButton = document.querySelector("#playOriginal");
const playEnhancedButton = document.querySelector("#playEnhanced");
const stopButton = document.querySelector("#stopPlayback");
const activeMode = document.querySelector("#activeMode");
const metricList = document.querySelector("#metricList");
const stemCount = document.querySelector("#stemCount");
const stemList = document.querySelector("#stemList");
const analysisStatus = document.querySelector("#analysisStatus");
const waveformCanvas = document.querySelector("#waveformCanvas");
const spectrumCanvas = document.querySelector("#spectrumCanvas");
const markerCount = document.querySelector("#markerCount");
const timelineList = document.querySelector("#timelineList");
const summary = document.querySelector("#summary");
const issueList = document.querySelector("#issueList");
const issueCount = document.querySelector("#issueCount");
const conflictCount = document.querySelector("#conflictCount");
const maskingList = document.querySelector("#maskingList");
const fixChain = document.querySelector("#fixChain");
const copyPresetButton = document.querySelector("#copyPreset");
const resetSessionButton = document.querySelector("#resetSession");
const copilotQuestion = document.querySelector("#copilotQuestion");
const askCopilotButton = document.querySelector("#askCopilot");
const copilotAnswer = document.querySelector("#copilotAnswer");
const pluginList = document.querySelector("#pluginList");

let audioContext;
let currentBuffer;
let currentSource;
let currentReport;
let currentStemAnalyses = [];
let currentReference;

const projectStoreKey = "auralyze.projects.v1";

const bandDefinitions = [
  { key: "sub", label: "Sub", min: 20, max: 60 },
  { key: "bass", label: "Bass", min: 60, max: 120 },
  { key: "lowMid", label: "Low mid", min: 120, max: 350 },
  { key: "mid", label: "Mid", min: 350, max: 2000 },
  { key: "presence", label: "Presence", min: 2000, max: 5000 },
  { key: "harsh", label: "Harsh", min: 5000, max: 8000 },
  { key: "air", label: "Air", min: 8000, max: 16000 },
];

const knowledgeBase = [
  {
    id: "mud-low-mid",
    topic: "Muddiness",
    keywords: ["mud", "muddy", "cloudy", "boxy", "low mid", "low-mid", "250", "300"],
    guidance: "Muddiness is usually excess 150-350 Hz energy or too many parts sharing the same body range.",
    move: "Cut the masking instrument first with a broad 1-3 dB move around 220-320 Hz before boosting clarity.",
  },
  {
    id: "vocal-presence",
    topic: "Vocal clarity",
    keywords: ["vocal", "voice", "dialog", "speech", "lyric", "clarity", "presence"],
    guidance: "Vocal intelligibility often depends on level, 2-5 kHz presence, and reduced masking from guitars, keys, or cymbals.",
    move: "Set vocal level first, carve 2-4 kHz pockets in competing stems, then add light compression and de-essing.",
  },
  {
    id: "kick-bass",
    topic: "Kick and bass",
    keywords: ["kick", "bass", "808", "sub", "low end", "low-end", "club"],
    guidance: "Kick and bass need separate ownership in the sub and bass ranges, otherwise the limiter reacts early and the groove loses punch.",
    move: "Choose one owner for 50-80 Hz, use sidechain or dynamic EQ, and keep sub frequencies mostly mono.",
  },
  {
    id: "harshness",
    topic: "Harshness",
    keywords: ["harsh", "sharp", "bright", "sibilance", "fatigue", "cymbal", "5k", "8k"],
    guidance: "Harshness often lives around 5-8 kHz, especially with vocals, cymbals, distorted guitars, and codec-heavy sources.",
    move: "Use dynamic EQ instead of a huge static cut, then restore air above 10 kHz only if the result becomes dull.",
  },
  {
    id: "dynamics",
    topic: "Dynamics",
    keywords: ["compression", "compressor", "dynamic", "flat", "punch", "crest", "loud"],
    guidance: "Crest factor describes the gap between peaks and average level; very low values can feel flat or tiring.",
    move: "Back off limiter gain, use slower attack where punch matters, and level-match before judging compression.",
  },
  {
    id: "reference",
    topic: "Reference matching",
    keywords: ["reference", "target", "match", "spotify", "youtube", "master", "mastering"],
    guidance: "Reference comparison only works when loudness is matched; otherwise the louder file usually feels better.",
    move: "Match perceived loudness first, then compare low end, vocal level, brightness, width, and dynamics.",
  },
  {
    id: "phase-stereo",
    topic: "Stereo and phase",
    keywords: ["phase", "stereo", "wide", "width", "mono", "correlation"],
    guidance: "Very wide low-frequency content and low stereo correlation can collapse on phones, clubs, and mono playback.",
    move: "Check mono, reduce widening on the mix bus, and center bass below roughly 100 Hz.",
  },
];

const db = (value) => 20 * Math.log10(Math.max(value, 1e-12));
const pct = (value) => `${Math.round(value * 100)}%`;
const formatDb = (value) => `${value.toFixed(1)} dB`;
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

audioInput.addEventListener("change", (event) => {
  const files = [...event.target.files];
  if (files.length) loadAudioFiles(files);
});

referenceInput.addEventListener("change", (event) => {
  const [file] = event.target.files;
  if (file) loadReferenceFile(file);
});

contentType.addEventListener("change", () => {
  if (!currentBuffer) return;
  runAnalysis(currentBuffer, currentStemAnalyses);
});

releaseTarget.addEventListener("change", () => {
  if (!currentBuffer) return;
  runAnalysis(currentBuffer, currentStemAnalyses);
});

uploadPanel.addEventListener("dragover", (event) => {
  event.preventDefault();
  uploadPanel.classList.add("dragover");
});

uploadPanel.addEventListener("dragleave", () => {
  uploadPanel.classList.remove("dragover");
});

uploadPanel.addEventListener("drop", (event) => {
  event.preventDefault();
  uploadPanel.classList.remove("dragover");
  const files = [...event.dataTransfer.files].filter((file) => file.type.startsWith("audio/"));
  if (files.length) loadAudioFiles(files);
});

playOriginalButton.addEventListener("click", () => playBuffer(false));
playEnhancedButton.addEventListener("click", () => playBuffer(true));
stopButton.addEventListener("click", stopPlayback);
exportWavButton.addEventListener("click", exportEnhancedAudio);
exportHtmlButton.addEventListener("click", exportHtmlReport);
exportReportButton.addEventListener("click", exportReport);
copyPresetButton.addEventListener("click", copyPresetChain);
resetSessionButton.addEventListener("click", resetSession);
saveProjectButton.addEventListener("click", saveProjectSnapshot);
deleteProjectButton.addEventListener("click", deleteSelectedProject);
exportProjectButton.addEventListener("click", exportProjectSnapshot);
projectImport.addEventListener("change", importProjectSnapshot);
projectLibrary.addEventListener("change", loadSelectedProject);
askCopilotButton.addEventListener("click", answerCopilotQuestion);
copilotQuestion.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && currentReport) answerCopilotQuestion();
});

drawEmptyState();
refreshProjectLibrary();

async function loadAudioFiles(files) {
  try {
    setStatus("Decoding");
    stopPlayback();
    fileName.textContent = files.length === 1 ? files[0].name : `${files.length} stems loaded`;
    audioContext = audioContext || new AudioContext();
    const decodedFiles = [];

    for (const file of files) {
      const arrayBuffer = await file.arrayBuffer();
      const buffer = await audioContext.decodeAudioData(arrayBuffer);
      decodedFiles.push({ file, buffer });
    }

    currentStemAnalyses = decodedFiles.map(({ file, buffer }) => analyzeStem(file, buffer));
    currentBuffer = decodedFiles.length === 1 ? decodedFiles[0].buffer : buildStemMix(decodedFiles.map((item) => item.buffer));
    runAnalysis(currentBuffer, currentStemAnalyses);
    playOriginalButton.disabled = false;
    playEnhancedButton.disabled = false;
    stopButton.disabled = false;
    exportWavButton.disabled = false;
    exportHtmlButton.disabled = false;
    exportReportButton.disabled = false;
    copyPresetButton.disabled = false;
    resetSessionButton.disabled = false;
    saveProjectButton.disabled = false;
    exportProjectButton.disabled = false;
    askCopilotButton.disabled = false;
  } catch (error) {
    console.error(error);
    setStatus("Could not read file");
    summary.textContent = "The browser could not decode this audio file. Try WAV, MP3, M4A, OGG, or FLAC.";
  }
}

async function loadReferenceFile(file) {
  try {
    setStatus("Reading reference");
    audioContext = audioContext || new AudioContext();
    const arrayBuffer = await file.arrayBuffer();
    const buffer = await audioContext.decodeAudioData(arrayBuffer);
    const mono = makeMono(buffer);
    currentReference = {
      name: file.name,
      metrics: analyzeTimeDomain(buffer, mono),
      spectral: analyzeSpectrum(mono, buffer.sampleRate),
    };
    if (currentBuffer) runAnalysis(currentBuffer, currentStemAnalyses);
  } catch (error) {
    console.error(error);
    setStatus("Reference failed");
    copilotAnswer.textContent = "The browser could not decode the reference file. Try another WAV, MP3, M4A, OGG, or FLAC.";
  }
}

function runAnalysis(buffer, stems = []) {
  setStatus("Analyzing");
  const mono = makeMono(buffer);
  const metrics = analyzeTimeDomain(buffer, mono);
  const spectral = analyzeSpectrum(mono, buffer.sampleRate);
  const timelineMarkers = analyzeTimeline(mono, buffer.sampleRate);
  const fixes = buildFixChain(metrics, spectral, contentType.value, releaseTarget.value);
  const stemConflicts = analyzeStemConflicts(stems);
  const stemIssues = diagnoseStemMix(stems, stemConflicts);
  const referenceComparison = currentReference ? compareReference(metrics, spectral, currentReference) : null;
  const referenceIssues = referenceComparison ? diagnoseReference(referenceComparison) : [];
  const baseIssues = diagnose(metrics, spectral, contentType.value);
  const actionIssues = [...stemIssues, ...referenceIssues];
  const issues = actionIssues.length ? [...baseIssues.filter((issue) => issue.severity !== "good"), ...actionIssues] : baseIssues;

  currentReport = {
    generatedAt: new Date().toISOString(),
    contentType: contentType.value,
    releaseTarget: releaseTarget.value,
    fileName: fileName.textContent,
    metrics,
    spectral,
    timelineMarkers,
    stems,
    stemConflicts,
    reference: currentReference,
    referenceComparison,
    issues,
    fixes,
  };

  drawWaveform(mono);
  drawSpectrum(spectral);
  renderMetrics(metrics);
  renderTimeline(timelineMarkers);
  renderStemAnalysis(stems);
  renderMasking(stemConflicts);
  renderDiagnosis(metrics, spectral, issues);
  renderFixChain(fixes);
  renderPluginRecommendations(buildPluginRecommendations(issues, fixes, stems, referenceComparison));
  setStatus("Analysis complete");
}

function buildStemMix(buffers) {
  const sampleRate = buffers[0].sampleRate;
  const channelCount = Math.min(2, Math.max(...buffers.map((buffer) => buffer.numberOfChannels)));
  const length = Math.min(...buffers.map((buffer) => buffer.length));
  const mixed = audioContext.createBuffer(channelCount, length, sampleRate);
  const mixGain = 1 / Math.max(2, Math.sqrt(buffers.length));

  for (let channel = 0; channel < channelCount; channel += 1) {
    const output = mixed.getChannelData(channel);
    for (const buffer of buffers) {
      const source = buffer.getChannelData(Math.min(channel, buffer.numberOfChannels - 1));
      for (let i = 0; i < length; i += 1) output[i] += source[i] * mixGain;
    }
  }

  return mixed;
}

function makeMono(buffer) {
  const output = new Float32Array(buffer.length);
  for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
    const data = buffer.getChannelData(channel);
    for (let i = 0; i < buffer.length; i += 1) output[i] += data[i] / buffer.numberOfChannels;
  }
  return output;
}

function analyzeTimeDomain(buffer, mono) {
  let peak = 0;
  let sumSquares = 0;
  let clipped = 0;
  let dc = 0;
  let silent = 0;
  const frameRms = [];
  const frameSize = Math.max(1024, Math.floor(buffer.sampleRate * 0.25));
  let frameSum = 0;
  let frameSamples = 0;

  for (let i = 0; i < mono.length; i += 1) {
    const value = mono[i];
    const abs = Math.abs(value);
    peak = Math.max(peak, abs);
    sumSquares += value * value;
    dc += value;
    if (abs > 0.995) clipped += 1;
    if (abs < 0.0005) silent += 1;
    frameSum += value * value;
    frameSamples += 1;
    if (frameSamples >= frameSize || i === mono.length - 1) {
      frameRms.push(Math.sqrt(frameSum / Math.max(frameSamples, 1)));
      frameSum = 0;
      frameSamples = 0;
    }
  }

  const rms = Math.sqrt(sumSquares / mono.length);
  const peakDb = db(peak);
  const loudnessDb = db(rms);
  const sortedFrameDb = frameRms.map(db).sort((a, b) => a - b);
  const noiseFloorDb = sortedFrameDb[Math.floor(sortedFrameDb.length * 0.1)] ?? db(rms);
  const lufsApprox = loudnessDb - 0.7;
  const truePeakDb = estimateTruePeakDb(mono);
  const crestFactor = peakDb - loudnessDb;
  const duration = buffer.duration;
  const stereo = analyzeStereo(buffer);

  return {
    duration,
    sampleRate: buffer.sampleRate,
    channels: buffer.numberOfChannels,
    peak,
    peakDb,
    truePeakDb,
    rms,
    loudnessDb,
    lufsApprox,
    noiseFloorDb,
    crestFactor,
    clippedRatio: clipped / mono.length,
    dcOffset: dc / mono.length,
    silenceRatio: silent / mono.length,
    stereo,
  };
}

function estimateTruePeakDb(samples) {
  let peak = 0;
  for (let i = 1; i < samples.length; i += 1) {
    const previous = samples[i - 1];
    const current = samples[i];
    peak = Math.max(peak, Math.abs(previous), Math.abs((previous + current) / 2), Math.abs(current));
  }
  return db(peak);
}

function analyzeTimeline(samples, sampleRate) {
  const windowSize = Math.max(2048, Math.floor(sampleRate * 1.2));
  const hop = Math.max(1024, Math.floor(windowSize / 2));
  const windows = [];

  for (let start = 0; start < samples.length; start += hop) {
    const end = Math.min(samples.length, start + windowSize);
    let sumSquares = 0;
    let peak = 0;
    let zeroLike = 0;
    let harshCrossings = 0;
    let previous = samples[start] || 0;

    for (let i = start; i < end; i += 1) {
      const value = samples[i];
      const abs = Math.abs(value);
      sumSquares += value * value;
      peak = Math.max(peak, abs);
      if (abs < 0.0005) zeroLike += 1;
      if ((value >= 0 && previous < 0) || (value < 0 && previous >= 0)) harshCrossings += 1;
      previous = value;
    }

    const size = Math.max(end - start, 1);
    windows.push({
      startSec: start / sampleRate,
      endSec: end / sampleRate,
      rmsDb: db(Math.sqrt(sumSquares / size)),
      peakDb: db(peak),
      silenceRatio: zeroLike / size,
      zeroCrossingRate: harshCrossings / size,
    });

    if (end === samples.length) break;
  }

  if (!windows.length) return [];
  const averageRms = average(windows.map((window) => window.rmsDb));
  const markers = [];

  for (const window of windows) {
    if (window.peakDb > -0.15) {
      markers.push(makeTimelineMarker(window, "critical", "Clipping risk", `Peak reaches ${formatDb(window.peakDb)}FS.`));
    } else if (window.rmsDb > averageRms + 6) {
      markers.push(makeTimelineMarker(window, "warning", "Loudness jump", `This section is ${formatDb(window.rmsDb - averageRms)} above the average window.`));
    } else if (window.rmsDb < averageRms - 14 && window.silenceRatio > 0.35) {
      markers.push(makeTimelineMarker(window, "warning", "Quiet gap", "This moment may disappear on small speakers or noisy environments."));
    } else if (window.zeroCrossingRate > 0.18 && window.rmsDb > averageRms - 8) {
      markers.push(makeTimelineMarker(window, "warning", "Harsh texture risk", "Fast waveform changes suggest bright/noisy content that may feel sharp."));
    }
  }

  return markers.slice(0, 10);
}

function makeTimelineMarker(window, severity, title, detail) {
  return {
    severity,
    title,
    detail,
    startSec: window.startSec,
    endSec: window.endSec,
    rmsDb: window.rmsDb,
    peakDb: window.peakDb,
  };
}

function analyzeStereo(buffer) {
  if (buffer.numberOfChannels < 2) {
    return { available: false, balanceDb: 0, correlation: 1, widthLabel: "Mono" };
  }

  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);
  let leftSq = 0;
  let rightSq = 0;
  let cross = 0;
  const step = Math.max(1, Math.floor(buffer.length / 300000));

  for (let i = 0; i < buffer.length; i += step) {
    leftSq += left[i] * left[i];
    rightSq += right[i] * right[i];
    cross += left[i] * right[i];
  }

  const leftRms = Math.sqrt(leftSq);
  const rightRms = Math.sqrt(rightSq);
  const balanceDb = db(leftRms / Math.max(rightRms, 1e-12));
  const correlation = cross / Math.max(Math.sqrt(leftSq * rightSq), 1e-12);
  const widthLabel = correlation > 0.92 ? "Narrow" : correlation < 0.25 ? "Very wide" : "Balanced";

  return { available: true, balanceDb, correlation, widthLabel };
}

function analyzeSpectrum(samples, sampleRate) {
  const fftSize = 4096;
  const frameCount = Math.min(70, Math.max(12, Math.floor(samples.length / fftSize)));
  const hop = Math.max(1, Math.floor((samples.length - fftSize) / frameCount));
  const bandEnergy = Object.fromEntries(bandDefinitions.map((band) => [band.key, 0]));
  const spectrumBins = new Float64Array(128);
  let totalEnergy = 0;
  let centroidTop = 0;
  let centroidBottom = 0;

  for (let frame = 0; frame < frameCount; frame += 1) {
    const start = Math.min(samples.length - fftSize, frame * hop);
    const real = new Float64Array(fftSize);
    const imag = new Float64Array(fftSize);

    for (let i = 0; i < fftSize; i += 1) {
      const window = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (fftSize - 1));
      real[i] = samples[start + i] * window;
    }

    fft(real, imag);

    for (let bin = 1; bin < fftSize / 2; bin += 1) {
      const frequency = (bin * sampleRate) / fftSize;
      const magnitude = real[bin] * real[bin] + imag[bin] * imag[bin];
      totalEnergy += magnitude;
      centroidTop += frequency * magnitude;
      centroidBottom += magnitude;
      for (const band of bandDefinitions) {
        if (frequency >= band.min && frequency < band.max) bandEnergy[band.key] += magnitude;
      }
      const visualIndex = Math.min(127, Math.floor((frequency / 16000) * 128));
      if (visualIndex >= 0) spectrumBins[visualIndex] += magnitude;
    }
  }

  const bands = {};
  for (const band of bandDefinitions) {
    bands[band.key] = bandEnergy[band.key] / Math.max(totalEnergy, 1e-12);
  }

  const maxSpectrum = Math.max(...spectrumBins, 1e-12);
  const visualSpectrum = Array.from(spectrumBins, (value) => Math.sqrt(value / maxSpectrum));

  return {
    bands,
    visualSpectrum,
    centroidHz: centroidTop / Math.max(centroidBottom, 1e-12),
  };
}

function analyzeStem(file, buffer) {
  const mono = makeMono(buffer);
  const metrics = analyzeTimeDomain(buffer, mono);
  const spectral = analyzeSpectrum(mono, buffer.sampleRate);
  return {
    id: crypto.randomUUID ? crypto.randomUUID() : `${file.name}-${Math.random()}`,
    name: file.name,
    role: inferStemRole(file.name, spectral),
    metrics,
    spectral,
  };
}

function inferStemRole(name, spectral) {
  const lower = name.toLowerCase();
  if (/(vox|vocal|voice|lead|rap|dialog|dialogue)/.test(lower)) return "vocal";
  if (/(kick|bd|bass drum)/.test(lower)) return "kick";
  if (/(bass|808|sub)/.test(lower)) return "bass";
  if (/(drum|perc|snare|hat|cymbal|beat)/.test(lower)) return "drums";
  if (/(guitar|gtr|riff)/.test(lower)) return "guitar";
  if (/(piano|keys|synth|pad|organ)/.test(lower)) return "keys";
  if (/(fx|impact|riser|sweep)/.test(lower)) return "fx";

  const bands = spectral.bands;
  if (bands.sub + bands.bass > 0.36) return "bass";
  if (bands.presence > 0.24 && bands.lowMid < 0.24) return "vocal";
  if (bands.harsh + bands.air > 0.26) return "drums";
  return "music";
}

function analyzeStemConflicts(stems) {
  if (stems.length < 2) return [];

  const conflicts = [];
  const vocal = stems.find((stem) => stem.role === "vocal");
  const kick = stems.find((stem) => stem.role === "kick");
  const bass = stems.find((stem) => stem.role === "bass");

  if (vocal) {
    for (const stem of stems) {
      if (stem === vocal || ["kick", "bass", "fx"].includes(stem.role)) continue;
      const overlap = bandOverlap(vocal, stem, ["mid", "presence"]);
      const competitorIsLoud = stem.metrics.loudnessDb > vocal.metrics.loudnessDb - 5;
      if (overlap > 0.23 && competitorIsLoud) {
        conflicts.push({
          severity: overlap > 0.32 ? "critical" : "warning",
          title: `Vocal masked by ${stem.role}`,
          stems: [vocal.name, stem.name],
          evidence: `Shared mid/presence energy score ${Math.round(overlap * 100)}; ${stem.role} is ${formatDb(stem.metrics.loudnessDb - vocal.metrics.loudnessDb)} relative to vocal.`,
          fix: `Dip ${stem.role} around 2-4 kHz when vocals are active, or lift vocal presence by 1-2 dB with de-essing after.`,
        });
      }
    }
  }

  if (kick && bass) {
    const lowOverlap = bandOverlap(kick, bass, ["sub", "bass"]);
    if (lowOverlap > 0.2 || Math.abs(kick.metrics.loudnessDb - bass.metrics.loudnessDb) < 4) {
      conflicts.push({
        severity: lowOverlap > 0.3 ? "critical" : "warning",
        title: "Kick and bass low-end collision",
        stems: [kick.name, bass.name],
        evidence: `Shared sub/bass score ${Math.round(lowOverlap * 100)}; level gap is ${formatDb(Math.abs(kick.metrics.loudnessDb - bass.metrics.loudnessDb))}.`,
        fix: "Choose which part owns 50-80 Hz, sidechain bass lightly from kick, and high-pass non-low-end instruments.",
      });
    }
  }

  for (let i = 0; i < stems.length; i += 1) {
    for (let j = i + 1; j < stems.length; j += 1) {
      const first = stems[i];
      const second = stems[j];
      if (new Set([first.role, second.role]).has("vocal")) continue;
      if (new Set([first.role, second.role]).has("kick") && new Set([first.role, second.role]).has("bass")) continue;
      const harshOverlap = bandOverlap(first, second, ["harsh", "air"]);
      if (harshOverlap > 0.18 && first.metrics.loudnessDb > -32 && second.metrics.loudnessDb > -32) {
        conflicts.push({
          severity: "warning",
          title: `${capitalize(first.role)} and ${second.role} brightness buildup`,
          stems: [first.name, second.name],
          evidence: `Shared harsh/air score ${Math.round(harshOverlap * 100)}.`,
          fix: "Use dynamic EQ on the brighter stem around 5-8 kHz and keep only one part carrying the top-end excitement.",
        });
      }
    }
  }

  return conflicts.slice(0, 6);
}

function bandOverlap(first, second, keys) {
  return keys.reduce((total, key) => {
    const a = first.spectral.bands[key] || 0;
    const b = second.spectral.bands[key] || 0;
    return total + Math.min(a, b) * Math.min(1.4, Math.max(first.metrics.rms, second.metrics.rms) / Math.max(Math.min(first.metrics.rms, second.metrics.rms), 1e-8));
  }, 0);
}

function diagnoseStemMix(stems, conflicts) {
  if (stems.length < 2) return [];
  const issues = conflicts.map((conflict) => ({
    severity: conflict.severity,
    title: conflict.title,
    evidence: conflict.evidence,
    explanation: `The stem comparison suggests ${conflict.stems.map((name) => `"${name}"`).join(" and ")} are competing in the same perceptual range.`,
    fix: conflict.fix,
  }));

  const vocal = stems.find((stem) => stem.role === "vocal");
  const instrumental = stems.filter((stem) => !["vocal", "fx"].includes(stem.role));
  if (vocal && instrumental.length) {
    const musicRms = average(instrumental.map((stem) => stem.metrics.loudnessDb));
    if (vocal.metrics.loudnessDb < musicRms - 7) {
      issues.push({
        severity: "warning",
        title: "Vocal may be under the track",
        evidence: `Vocal RMS is ${formatDb(vocal.metrics.loudnessDb)}, while backing stems average ${formatDb(musicRms)}.`,
        explanation: "A large level gap makes lyric intelligibility depend too much on EQ tricks.",
        fix: "Raise vocal level 2-4 dB before adding presence boosts or heavy compression.",
      });
    }
  }

  return issues;
}

function compareReference(metrics, spectral, reference) {
  const bandDiffs = {};
  for (const band of bandDefinitions) {
    bandDiffs[band.key] = (spectral.bands[band.key] || 0) - (reference.spectral.bands[band.key] || 0);
  }

  return {
    name: reference.name,
    loudnessGapDb: metrics.loudnessDb - reference.metrics.loudnessDb,
    dynamicsGapDb: metrics.crestFactor - reference.metrics.crestFactor,
    centroidGapHz: spectral.centroidHz - reference.spectral.centroidHz,
    bandDiffs,
  };
}

function diagnoseReference(comparison) {
  const issues = [];
  const diffs = comparison.bandDiffs;

  if (Math.abs(comparison.loudnessGapDb) > 4) {
    issues.push({
      severity: "warning",
      title: "Reference loudness mismatch",
      evidence: `Your audio is ${formatDb(comparison.loudnessGapDb)} RMS relative to "${comparison.name}".`,
      explanation: "Large loudness gaps make tonal decisions unreliable because louder usually feels better.",
      fix: comparison.loudnessGapDb < 0 ? "Raise overall level after mix fixes, or use mastering gain with limiter headroom." : "Lower the master and compare at matched loudness before changing EQ.",
    });
  }

  if (diffs.lowMid > 0.08 && diffs.presence < 0.02) {
    issues.push({
      severity: "warning",
      title: "Darker than the reference",
      evidence: `Low mids are ${pct(Math.abs(diffs.lowMid))} above reference while presence is not stronger.`,
      explanation: "Compared with the target, the mix may feel cloudy or less forward.",
      fix: "Reduce 200-350 Hz buildup and add a controlled 2-4 kHz lift only where clarity is needed.",
    });
  }

  if (diffs.harsh + diffs.air > 0.1) {
    issues.push({
      severity: "warning",
      title: "Brighter than the reference",
      evidence: `Upper bands exceed the reference by ${pct(diffs.harsh + diffs.air)}.`,
      explanation: "Extra top-end can sound exciting briefly but tiring over time.",
      fix: "Use dynamic EQ around 5-8 kHz and compare cymbals, sibilance, and vocal consonants at matched loudness.",
    });
  }

  if (Math.abs(comparison.dynamicsGapDb) > 6) {
    issues.push({
      severity: "warning",
      title: "Dynamics differ strongly from reference",
      evidence: `Crest factor gap is ${formatDb(comparison.dynamicsGapDb)}.`,
      explanation: "The audio may feel much flatter or more jumpy than the target.",
      fix: comparison.dynamicsGapDb < 0 ? "Ease bus compression or limiter gain." : "Use gentle compression or automation to stabilize level swings.",
    });
  }

  return issues;
}

function diagnose(metrics, spectral, type) {
  const issues = [];
  const bands = spectral.bands;

  if (metrics.clippedRatio > 0.0005) {
    issues.push({
      severity: "critical",
      title: "Clipping is damaging the signal",
      evidence: `${pct(metrics.clippedRatio)} of samples hit near full scale; peak is ${formatDb(metrics.peakDb)}FS.`,
      explanation: "Clipping creates brittle distortion that cannot be fixed cleanly with normal EQ or compression.",
      fix: "Lower the source gain, use a limiter with headroom, and repair clipped sections before mastering.",
    });
  } else if (metrics.peakDb > -0.2) {
    issues.push({
      severity: "warning",
      title: "Peak headroom is almost gone",
      evidence: `Peak is ${formatDb(metrics.peakDb)}FS.`,
      explanation: "The file is very close to digital ceiling, so later processing can create inter-sample distortion.",
      fix: "Trim the mix by 1-3 dB before adding EQ, compression, or limiting.",
    });
  }

  if (metrics.crestFactor < 7) {
    issues.push({
      severity: "warning",
      title: "Dynamics are heavily squeezed",
      evidence: `Crest factor is ${metrics.crestFactor.toFixed(1)} dB.`,
      explanation: "Low crest factor often means transients are flattened and the sound may feel tiring.",
      fix: "Ease limiter gain, slow compression release, or use parallel compression instead of full compression.",
    });
  } else if (metrics.crestFactor > 22 && type !== "film") {
    issues.push({
      severity: "warning",
      title: "Dynamics may be too uneven",
      evidence: `Crest factor is ${metrics.crestFactor.toFixed(1)} dB.`,
      explanation: "Large level swings can make quiet details disappear and loud moments jump out.",
      fix: "Use gentle compression or volume automation before final loudness normalization.",
    });
  }

  if (bands.lowMid > 0.24 && bands.presence < 0.2) {
    issues.push({
      severity: "warning",
      title: "Likely muddiness in the low mids",
      evidence: `Low-mid energy is ${pct(bands.lowMid)} while presence is ${pct(bands.presence)}.`,
      explanation: "Energy around 120-350 Hz can hide vocal and instrument detail when it dominates the mix.",
      fix: "Try a broad 1-3 dB cut around 220-320 Hz and rebalance bass fundamentals separately.",
    });
  }

  if (bands.bass + bands.sub > 0.34) {
    issues.push({
      severity: "warning",
      title: "Low end may be overpowering",
      evidence: `Sub and bass bands hold ${pct(bands.sub + bands.bass)} of measured energy.`,
      explanation: "Too much low-frequency energy reduces clarity and can trigger limiters early.",
      fix: "High-pass non-bass tracks, control 50-120 Hz with dynamic EQ, and check kick/bass masking.",
    });
  }

  if (bands.harsh > 0.14) {
    issues.push({
      severity: "warning",
      title: "Harshness risk in the upper mids",
      evidence: `5-8 kHz energy is ${pct(bands.harsh)}.`,
      explanation: "Excess energy here can make vocals, cymbals, and guitars feel sharp or fatiguing.",
      fix: "Use dynamic EQ around 5-7 kHz, then restore air above 10 kHz if the result becomes dull.",
    });
  }

  if ((type === "voice" || type === "film") && bands.presence < 0.12) {
    issues.push({
      severity: "warning",
      title: "Speech clarity may be low",
      evidence: `Presence band is only ${pct(bands.presence)}.`,
      explanation: "Dialogue intelligibility often depends on controlled energy around 2-5 kHz.",
      fix: "Add a small presence boost, reduce masking instruments, and use light de-essing after the boost.",
    });
  }

  if (metrics.stereo.available && Math.abs(metrics.stereo.balanceDb) > 1.5) {
    issues.push({
      severity: "warning",
      title: "Stereo balance leans to one side",
      evidence: `Left/right RMS difference is ${formatDb(metrics.stereo.balanceDb)}.`,
      explanation: "A level imbalance can make the mix feel pulled away from center.",
      fix: "Recenter the stereo bus or correct the louder side before widening decisions.",
    });
  }

  if (metrics.stereo.available && metrics.stereo.correlation < 0.15) {
    issues.push({
      severity: "critical",
      title: "Phase cancellation risk",
      evidence: `Stereo correlation is ${metrics.stereo.correlation.toFixed(2)}.`,
      explanation: "Very low correlation can collapse badly on mono speakers and phones.",
      fix: "Check polarity, reduce stereo widening, and keep bass frequencies more mono.",
    });
  }

  if (Math.abs(metrics.dcOffset) > 0.01) {
    issues.push({
      severity: "warning",
      title: "DC offset detected",
      evidence: `Average waveform offset is ${metrics.dcOffset.toFixed(3)}.`,
      explanation: "DC offset wastes headroom and can make dynamics processors react poorly.",
      fix: "Apply DC offset removal or a very low high-pass filter around 20 Hz.",
    });
  }

  if (issues.length === 0) {
    issues.push({
      severity: "good",
      title: "No major technical issue detected",
      evidence: `Peak ${formatDb(metrics.peakDb)}FS, dynamics ${metrics.crestFactor.toFixed(1)} dB.`,
      explanation: "The file has healthy basic signal behavior according to this first-pass analysis.",
      fix: "Use a reference track next and compare tonal balance, vocal level, and master loudness.",
    });
  }

  return issues;
}

function buildFixChain(metrics, spectral, type, target) {
  const bands = spectral.bands;
  const chain = [
    {
      name: "Input trim",
      detail: metrics.peakDb > -1 ? "Reduce input by 2 dB for safer processing headroom." : "Keep input gain unchanged.",
      settings: { gain: metrics.peakDb > -1 ? 0.8 : 1 },
    },
    {
      name: "Sub cleanup",
      detail: "High-pass below 30 Hz to remove inaudible rumble and DC energy.",
      settings: { highpassHz: 30 },
    },
  ];

  if (bands.lowMid > 0.24) {
    chain.push({
      name: "Mud control",
      detail: "Broad low-mid cut around 280 Hz.",
      settings: { type: "peaking", frequency: 280, q: 0.9, gain: -2.5 },
    });
  }

  if (bands.presence < 0.15 || type === "voice" || type === "film") {
    chain.push({
      name: "Clarity lift",
      detail: "Small presence boost around 3.2 kHz for better intelligibility.",
      settings: { type: "peaking", frequency: 3200, q: 0.8, gain: 1.8 },
    });
  }

  if (bands.harsh > 0.14) {
    chain.push({
      name: "Harshness softener",
      detail: "Gentle cut around 6.2 kHz to reduce fatigue.",
      settings: { type: "peaking", frequency: 6200, q: 1.2, gain: -2 },
    });
  }

  if (metrics.crestFactor > 16 || type === "voice") {
    chain.push({
      name: "Level stabilizer",
      detail: "Light compression to reduce jumps while keeping transients alive.",
      settings: { threshold: -20, ratio: 2.2, attack: 0.012, release: 0.18 },
    });
  }

  if (target === "podcast" || type === "voice") {
    chain.push({
      name: "Speech target",
      detail: "Prioritize steady voice level and controlled sibilance for spoken-word release.",
      settings: { type: "peaking", frequency: 4200, q: 0.9, gain: 1.2 },
    });
  }

  if (target === "club") {
    chain.push({
      name: "Club translation",
      detail: "Add a restrained low-shelf lift for larger systems after low-end cleanup.",
      settings: { type: "lowshelf", frequency: 90, q: 0.7, gain: 1.5 },
    });
  }

  if (target === "cinema") {
    chain.push({
      name: "Cinema headroom",
      detail: "Preserve transient headroom and avoid over-limiting for wide dynamic playback.",
      settings: { gain: 0.92 },
    });
  }

  if (target === "streaming" || target === "youtube") {
    chain.push({
      name: "Streaming polish",
      detail: "Add gentle high-shelf air and keep limiter headroom for codec conversion.",
      settings: { type: "highshelf", frequency: 10000, q: 0.7, gain: 0.9 },
    });
  }

  chain.push({
    name: "Release target note",
    detail: targetDescription(target),
    settings: { target },
  });

  return chain;
}

function targetDescription(target) {
  const descriptions = {
    balanced: "Balanced preview: conservative correction without aggressive loudness shaping.",
    streaming: "Streaming target: translation-focused tone with headroom for platform normalization.",
    youtube: "YouTube target: stable voice/music balance and codec-safe high-end.",
    club: "Club target: stronger low-end confidence while protecting kick/bass separation.",
    cinema: "Cinema target: wider dynamics and safer peak headroom.",
    podcast: "Podcast target: speech intelligibility, steady level, and reduced fatigue.",
  };
  return descriptions[target] || descriptions.balanced;
}

function renderMetrics(metrics) {
  metricList.innerHTML = `
    <div><dt>Peak</dt><dd>${formatDb(metrics.peakDb)}FS</dd></div>
    <div><dt>True peak</dt><dd>${formatDb(metrics.truePeakDb)}TP</dd></div>
    <div><dt>Loudness</dt><dd>${formatDb(metrics.lufsApprox)} LUFS*</dd></div>
    <div><dt>Noise floor</dt><dd>${formatDb(metrics.noiseFloorDb)}</dd></div>
    <div><dt>Dynamics</dt><dd>${metrics.crestFactor.toFixed(1)} dB</dd></div>
    <div><dt>Stereo</dt><dd>${metrics.stereo.widthLabel}</dd></div>
  `;
}

function renderTimeline(markers) {
  markerCount.textContent = `${markers.length} ${markers.length === 1 ? "marker" : "markers"}`;
  if (!markers.length) {
    timelineList.innerHTML = '<p class="empty-note">No obvious time-based problems detected in this pass.</p>';
    return;
  }

  timelineList.innerHTML = markers
    .map(
      (marker) => `
        <article class="timeline-row">
          <div class="timeline-time">${formatTime(marker.startSec)}</div>
          <div>
            <div class="timeline-title">${escapeHtml(marker.title)}</div>
            <div class="timeline-copy">${escapeHtml(marker.detail)} Window RMS ${formatDb(marker.rmsDb)}.</div>
          </div>
          <span class="timeline-severity">${escapeHtml(marker.severity)}</span>
        </article>
      `,
    )
    .join("");
}

function renderStemAnalysis(stems) {
  stemCount.textContent = `${stems.length} ${stems.length === 1 ? "stem" : "stems"}`;
  if (stems.length < 2) {
    stemList.innerHTML = `<p class="empty-note">${stems.length === 1 ? "Single-file mode active. Add stems to compare track roles." : "Upload multiple stems to detect masking and balance issues."}</p>`;
    return;
  }

  stemList.innerHTML = stems
    .map((stem) => {
      const bands = stem.spectral.bands;
      const low = clamp((bands.sub + bands.bass) * 170, 4, 100);
      const body = clamp((bands.lowMid + bands.mid) * 130, 4, 100);
      const clarity = clamp(bands.presence * 220, 4, 100);
      const bright = clamp((bands.harsh + bands.air) * 190, 4, 100);
      return `
        <article class="stem-row">
          <div class="stem-top">
            <span class="stem-name" title="${escapeHtml(stem.name)}">${escapeHtml(stem.name)}</span>
            <span class="role-pill">${escapeHtml(stem.role)}</span>
          </div>
          <div class="stem-meter" aria-label="Stem spectral energy">
            <span style="--value:${low}%"></span>
            <span style="--value:${body}%"></span>
            <span style="--value:${clarity}%"></span>
            <span style="--value:${bright}%"></span>
          </div>
          <div class="stem-meta">Peak ${formatDb(stem.metrics.peakDb)}FS, loudness ${formatDb(stem.metrics.loudnessDb)} RMS</div>
        </article>
      `;
    })
    .join("");
}

function renderMasking(conflicts) {
  conflictCount.textContent = `${conflicts.length} ${conflicts.length === 1 ? "conflict" : "conflicts"}`;
  if (!conflicts.length) {
    maskingList.innerHTML = `<p class="empty-note">${currentStemAnalyses.length > 1 ? "No obvious stem masking detected in this first-pass scan." : "Add stems to reveal frequency collisions between parts."}</p>`;
    return;
  }

  maskingList.innerHTML = conflicts
    .map(
      (conflict) => `
        <article class="mask-row ${conflict.severity}">
          <div class="mask-top">
            <span class="mask-title">${escapeHtml(conflict.title)}</span>
            <span class="role-pill">${escapeHtml(conflict.severity)}</span>
          </div>
          <div class="mask-copy">${escapeHtml(conflict.evidence)}</div>
          <div class="mask-copy"><strong>Move:</strong> ${escapeHtml(conflict.fix)}</div>
        </article>
      `,
    )
    .join("");
}

function renderDiagnosis(metrics, spectral, issues) {
  const majorIssues = issues.filter((issue) => issue.severity !== "good").length;
  issueCount.textContent = `${majorIssues} ${majorIssues === 1 ? "issue" : "issues"}`;
  summary.textContent = buildSummary(metrics, spectral, issues);
  issueList.innerHTML = issues
    .map(
      (issue) => `
        <article class="issue-card ${issue.severity}">
          <h3>${issue.title}</h3>
          <p class="evidence">${issue.evidence}</p>
          <p>${issue.explanation}</p>
          <p><strong>Suggested fix:</strong> ${issue.fix}</p>
        </article>
      `,
    )
    .join("");
}

function buildSummary(metrics, spectral, issues) {
  const severe = issues.some((issue) => issue.severity === "critical");
  const issueText = issues.filter((issue) => issue.severity !== "good").length;
  if (severe) {
    return `I found ${issueText} technical problem${issueText === 1 ? "" : "s"}, including at least one critical issue. Fix clipping or phase risk before creative mixing decisions.`;
  }
  if (issueText > 0) {
    return `I found ${issueText} likely improvement area${issueText === 1 ? "" : "s"}. The strongest clues are tonal balance, dynamics, and stereo behavior.`;
  }
  return `The file looks technically healthy. Spectral centroid is around ${Math.round(spectral.centroidHz)} Hz, with ${metrics.crestFactor.toFixed(1)} dB of dynamics.`;
}

function renderFixChain(chain) {
  fixChain.innerHTML = chain
    .map(
      (step, index) => `
        <div class="fix-step">
          <strong>${index + 1}. ${step.name}</strong>
          <span>${step.detail}</span>
        </div>
      `,
    )
    .join("");
}

function buildPluginRecommendations(issues, fixes, stems, referenceComparison) {
  if (!currentReport) return [];
  const recommendations = [];
  const text = issues.map((issue) => `${issue.title} ${issue.fix}`).join(" ").toLowerCase();

  if (/mud|low-mid|darker|cloudy|harsh|presence|clarity|reference/.test(text)) {
    recommendations.push({
      type: "EQ",
      name: "Dynamic EQ",
      reason: "Best first tool for mud cuts, vocal clarity boosts, harshness control, and reference matching.",
      move: "Use broad static moves first, then dynamic bands only where the problem appears.",
    });
  }

  if (/dynamics|compression|level|vocal may be under|speech/.test(text) || fixes.some((fix) => fix.name.includes("Level"))) {
    recommendations.push({
      type: "Dynamics",
      name: "Compressor",
      reason: "Useful for stabilizing vocals, podcasts, and uneven performances before mastering.",
      move: "Aim for 2-4 dB gain reduction, then level-match before judging.",
    });
  }

  if (/clipping|headroom|ceiling|streaming|youtube/.test(text) || ["streaming", "youtube"].includes(releaseTarget.value)) {
    recommendations.push({
      type: "Mastering",
      name: "True-peak limiter",
      reason: "Protects the output from clipping and codec overs after EQ and compression.",
      move: "Leave ceiling below 0 dBFS and avoid pushing loudness before mix issues are fixed.",
    });
  }

  if (/phase|stereo|wide|mono/.test(text)) {
    recommendations.push({
      type: "Stereo",
      name: "Stereo utility",
      reason: "Needed for mono checks, width control, and low-end centering.",
      move: "Mono bass below roughly 100 Hz and reduce widening if correlation gets too low.",
    });
  }

  if (/kick|bass|low-end|sub|808/.test(text) || stems.some((stem) => ["kick", "bass"].includes(stem.role))) {
    recommendations.push({
      type: "Low end",
      name: "Sidechain or dynamic EQ",
      reason: "Helps kick and bass share space without permanently thinning either part.",
      move: "Trigger a small bass dip from the kick around the shared fundamental range.",
    });
  }

  if (referenceComparison) {
    recommendations.push({
      type: "Reference",
      name: "A/B loudness matcher",
      reason: "Reference judgments are unreliable until the two tracks are level matched.",
      move: "Match perceived loudness before changing EQ to chase the reference.",
    });
  }

  if (!recommendations.length) {
    recommendations.push({
      type: "Utility",
      name: "Reference meter",
      reason: "The current file has no obvious technical emergency, so metering and references become the best guide.",
      move: "Check loudness, spectrum, stereo correlation, and mono translation.",
    });
  }

  return recommendations.slice(0, 6);
}

function renderPluginRecommendations(recommendations) {
  pluginList.innerHTML = recommendations
    .map(
      (item) => `
        <article class="plugin-card">
          <span class="plugin-tag">${escapeHtml(item.type)}</span>
          <strong>${escapeHtml(item.name)}</strong>
          <span>${escapeHtml(item.reason)}</span>
          <span><strong>Move:</strong> ${escapeHtml(item.move)}</span>
        </article>
      `,
    )
    .join("");
}

function drawEmptyState() {
  const wave = waveformCanvas.getContext("2d");
  const spectrum = spectrumCanvas.getContext("2d");
  drawGrid(wave, waveformCanvas.width, waveformCanvas.height);
  drawCenteredText(wave, "Upload audio to see the waveform");
  drawGrid(spectrum, spectrumCanvas.width, spectrumCanvas.height);
  drawCenteredText(spectrum, "Frequency analysis appears here");
}

function drawWaveform(samples) {
  const ctx = waveformCanvas.getContext("2d");
  const { width, height } = waveformCanvas;
  drawGrid(ctx, width, height);
  ctx.strokeStyle = "#0b7a75";
  ctx.lineWidth = 2;
  ctx.beginPath();

  const samplesPerPixel = Math.max(1, Math.floor(samples.length / width));
  for (let x = 0; x < width; x += 1) {
    let min = 1;
    let max = -1;
    const start = x * samplesPerPixel;
    for (let i = 0; i < samplesPerPixel && start + i < samples.length; i += 1) {
      const value = samples[start + i];
      min = Math.min(min, value);
      max = Math.max(max, value);
    }
    const y1 = ((1 - max) * height) / 2;
    const y2 = ((1 - min) * height) / 2;
    ctx.moveTo(x, y1);
    ctx.lineTo(x, y2);
  }
  ctx.stroke();
}

function drawSpectrum(spectral) {
  const ctx = spectrumCanvas.getContext("2d");
  const { width, height } = spectrumCanvas;
  drawGrid(ctx, width, height);
  const barWidth = width / spectral.visualSpectrum.length;

  spectral.visualSpectrum.forEach((value, index) => {
    const barHeight = clamp(value, 0, 1) * (height - 34);
    const hueMix = index / spectral.visualSpectrum.length;
    ctx.fillStyle = hueMix < 0.35 ? "#0b7a75" : hueMix < 0.7 ? "#b7791f" : "#db5f4b";
    ctx.fillRect(index * barWidth, height - barHeight, Math.max(1, barWidth - 1), barHeight);
  });

  ctx.fillStyle = "#65706e";
  ctx.font = "700 13px Inter, sans-serif";
  ctx.fillText("20 Hz", 14, height - 12);
  ctx.fillText("16 kHz", width - 58, height - 12);
}

function drawGrid(ctx, width, height) {
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#fbfbf8";
  ctx.fillRect(0, 0, width, height);
  ctx.strokeStyle = "#e5e7df";
  ctx.lineWidth = 1;
  for (let x = 0; x <= width; x += width / 12) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
    ctx.stroke();
  }
  for (let y = 0; y <= height; y += height / 4) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }
}

function drawCenteredText(ctx, text) {
  ctx.fillStyle = "#65706e";
  ctx.font = "800 22px Inter, sans-serif";
  ctx.textAlign = "center";
  ctx.fillText(text, ctx.canvas.width / 2, ctx.canvas.height / 2);
  ctx.textAlign = "start";
}

function playBuffer(enhanced) {
  if (!currentBuffer) return;
  stopPlayback();
  audioContext = audioContext || new AudioContext();
  const source = audioContext.createBufferSource();
  source.buffer = currentBuffer;
  currentSource = source;

  let tail = source;
  if (enhanced && currentReport) {
    tail = applyPreviewChain(source, currentReport.fixes, audioContext);
  }

  tail.connect(audioContext.destination);
  source.start();
  activeMode.textContent = enhanced ? "Playing enhanced preview" : "Playing original";
  source.onended = () => {
    activeMode.textContent = "Playback finished";
    currentSource = null;
  };
}

function applyPreviewChain(source, chain, context) {
  let previous = source;
  for (const step of chain) {
    if (step.settings.highpassHz) {
      const filter = context.createBiquadFilter();
      filter.type = "highpass";
      filter.frequency.value = step.settings.highpassHz;
      previous.connect(filter);
      previous = filter;
    }
    if (step.settings.type === "peaking") {
      const filter = context.createBiquadFilter();
      filter.type = "peaking";
      filter.frequency.value = step.settings.frequency;
      filter.Q.value = step.settings.q;
      filter.gain.value = step.settings.gain;
      previous.connect(filter);
      previous = filter;
    }
    if (step.settings.type === "lowshelf" || step.settings.type === "highshelf") {
      const filter = context.createBiquadFilter();
      filter.type = step.settings.type;
      filter.frequency.value = step.settings.frequency;
      filter.Q.value = step.settings.q;
      filter.gain.value = step.settings.gain;
      previous.connect(filter);
      previous = filter;
    }
    if (step.settings.threshold) {
      const compressor = context.createDynamicsCompressor();
      compressor.threshold.value = step.settings.threshold;
      compressor.ratio.value = step.settings.ratio;
      compressor.attack.value = step.settings.attack;
      compressor.release.value = step.settings.release;
      previous.connect(compressor);
      previous = compressor;
    }
    if (step.settings.gain) {
      const gain = context.createGain();
      gain.gain.value = step.settings.gain;
      previous.connect(gain);
      previous = gain;
    }
  }
  return previous;
}

function stopPlayback() {
  if (currentSource) {
    try {
      currentSource.stop();
    } catch (error) {
      console.warn(error);
    }
  }
  currentSource = null;
  activeMode.textContent = currentBuffer ? "Stopped" : "Waiting for audio";
}

async function exportEnhancedAudio() {
  if (!currentBuffer || !currentReport) return;
  setStatus("Rendering WAV");
  exportWavButton.disabled = true;

  try {
    const offline = new OfflineAudioContext(currentBuffer.numberOfChannels, currentBuffer.length, currentBuffer.sampleRate);
    const source = offline.createBufferSource();
    source.buffer = currentBuffer;
    const tail = applyPreviewChain(source, currentReport.fixes, offline);
    tail.connect(offline.destination);
    source.start(0);
    const renderedBuffer = await offline.startRendering();
    const blob = encodeWav(renderedBuffer);
    downloadBlob(blob, `${safeBaseName(currentReport.fileName)}-enhanced.wav`);
    setStatus("WAV exported");
  } catch (error) {
    console.error(error);
    setStatus("Export failed");
  } finally {
    exportWavButton.disabled = false;
  }
}

function exportReport() {
  if (!currentReport) return;
  const blob = new Blob([JSON.stringify(currentReport, null, 2)], { type: "application/json" });
  downloadBlob(blob, `${safeBaseName(currentReport.fileName)}-auralyze-report.json`);
}

function exportHtmlReport() {
  if (!currentReport) return;
  const html = buildHtmlReport(currentReport);
  const blob = new Blob([html], { type: "text/html" });
  downloadBlob(blob, `${safeBaseName(currentReport.projectName || currentReport.fileName)}-auralyze-report.html`);
}

function saveProjectSnapshot() {
  if (!currentReport) return;
  const name = projectName.value.trim() || safeBaseName(currentReport.fileName) || "Untitled project";
  const projects = readProjects();
  const id = currentReport.projectId || `project-${Date.now()}`;
  const savedReport = {
    ...currentReport,
    projectId: id,
    projectName: name,
    savedAt: new Date().toISOString(),
  };
  currentReport = savedReport;
  projects[id] = savedReport;
  writeProjects(projects);
  refreshProjectLibrary(id);
  deleteProjectButton.disabled = false;
  exportProjectButton.disabled = false;
  copilotAnswer.textContent = `Saved "${name}" locally. Audio files are not stored, but the full diagnosis and settings are.`;
}

function loadSelectedProject() {
  const id = projectLibrary.value;
  if (!id) return;
  const report = readProjects()[id];
  if (!report) return;
  currentReport = report;
  currentBuffer = null;
  currentStemAnalyses = report.stems || [];
  currentReference = report.reference || null;
  projectName.value = report.projectName || "";
  contentType.value = report.contentType || "music";
  releaseTarget.value = report.releaseTarget || "balanced";
  fileName.textContent = report.fileName || "Saved project";
  activeMode.textContent = "Saved analysis loaded";
  summary.textContent = buildSummary(report.metrics, report.spectral, report.issues);
  renderMetrics(report.metrics);
  renderTimeline(report.timelineMarkers || []);
  renderStemAnalysis(report.stems || []);
  renderMasking(report.stemConflicts || []);
  renderDiagnosis(report.metrics, report.spectral, report.issues || []);
  renderFixChain(report.fixes || []);
  renderPluginRecommendations(buildPluginRecommendations(report.issues || [], report.fixes || [], report.stems || [], report.referenceComparison));
  drawEmptyState();
  setStatus("Saved project loaded");

  playOriginalButton.disabled = true;
  playEnhancedButton.disabled = true;
  stopButton.disabled = true;
  exportWavButton.disabled = true;
  exportHtmlButton.disabled = false;
  exportReportButton.disabled = false;
  copyPresetButton.disabled = false;
  resetSessionButton.disabled = false;
  saveProjectButton.disabled = false;
  deleteProjectButton.disabled = false;
  exportProjectButton.disabled = false;
  askCopilotButton.disabled = false;
}

function deleteSelectedProject() {
  const id = projectLibrary.value || currentReport?.projectId;
  if (!id) return;
  const projects = readProjects();
  const name = projects[id]?.projectName || "project";
  delete projects[id];
  writeProjects(projects);
  refreshProjectLibrary();
  deleteProjectButton.disabled = true;
  copilotAnswer.textContent = `Deleted "${name}" from local project memory.`;
}

function buildHtmlReport(report) {
  const issues = report.issues || [];
  const markers = report.timelineMarkers || [];
  const conflicts = report.stemConflicts || [];
  const stems = report.stems || [];
  const plugins = buildPluginRecommendations(issues, report.fixes || [], stems, report.referenceComparison);
  const rows = [
    ["File", report.fileName],
    ["Project", report.projectName || "Untitled"],
    ["Content", report.contentType],
    ["Release", report.releaseTarget],
    ["Peak", `${formatDb(report.metrics.peakDb)}FS`],
    ["True peak", `${formatDb(report.metrics.truePeakDb)}TP`],
    ["Loudness", `${formatDb(report.metrics.lufsApprox)} LUFS approx`],
    ["Dynamics", `${report.metrics.crestFactor.toFixed(1)} dB`],
    ["Noise floor", formatDb(report.metrics.noiseFloorDb)],
  ];

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Auralyze Report - ${escapeHtml(report.projectName || report.fileName || "Audio")}</title>
  <style>
    body{margin:0;background:#f7f5ef;color:#1d2525;font-family:Inter,Arial,sans-serif;line-height:1.5}
    main{width:min(1040px,calc(100% - 32px));margin:0 auto;padding:32px 0}
    h1{font-size:42px;margin:0 0 6px} h2{font-size:20px;margin:0 0 12px}
    section{background:white;border:1px solid #d9ddd5;border-radius:8px;padding:18px;margin:14px 0}
    table{border-collapse:collapse;width:100%} td{border-bottom:1px solid #e5e7df;padding:8px} td:first-child{color:#65706e;font-weight:700;width:180px}
    article{border-left:5px solid #0b7a75;background:#fbfbf8;border-radius:8px;padding:12px;margin:10px 0}
    .warning{border-left-color:#b7791f}.critical{border-left-color:#db5f4b}.good{border-left-color:#2d7d4f}
    .muted{color:#65706e}.tag{display:inline-block;background:#eef8f5;color:#075b57;border-radius:999px;padding:3px 8px;font-size:12px;font-weight:800}
  </style>
</head>
<body>
<main>
  <p class="muted">Auralyze audio diagnosis report</p>
  <h1>${escapeHtml(report.projectName || report.fileName || "Audio Report")}</h1>
  <p class="muted">Generated ${escapeHtml(new Date(report.generatedAt || Date.now()).toLocaleString())}</p>
  <section><h2>Summary</h2><p>${escapeHtml(buildSummary(report.metrics, report.spectral, issues))}</p></section>
  <section><h2>Metrics</h2><table>${rows.map(([key, value]) => `<tr><td>${escapeHtml(key)}</td><td>${escapeHtml(value ?? "-")}</td></tr>`).join("")}</table></section>
  <section><h2>Diagnosis</h2>${issues.map((issue) => `<article class="${escapeHtml(issue.severity)}"><span class="tag">${escapeHtml(issue.severity)}</span><h3>${escapeHtml(issue.title)}</h3><p><strong>Evidence:</strong> ${escapeHtml(issue.evidence)}</p><p>${escapeHtml(issue.explanation)}</p><p><strong>Fix:</strong> ${escapeHtml(issue.fix)}</p></article>`).join("") || "<p>No issues detected.</p>"}</section>
  <section><h2>Timeline</h2>${markers.map((marker) => `<article class="${escapeHtml(marker.severity)}"><span class="tag">${formatTime(marker.startSec)}</span><h3>${escapeHtml(marker.title)}</h3><p>${escapeHtml(marker.detail)}</p></article>`).join("") || "<p>No timeline markers.</p>"}</section>
  <section><h2>Stem Conflicts</h2>${conflicts.map((conflict) => `<article class="${escapeHtml(conflict.severity)}"><h3>${escapeHtml(conflict.title)}</h3><p>${escapeHtml(conflict.evidence)}</p><p><strong>Move:</strong> ${escapeHtml(conflict.fix)}</p></article>`).join("") || "<p>No stem conflicts saved.</p>"}</section>
  <section><h2>Processing Chain</h2>${(report.fixes || []).map((fix, index) => `<article><h3>${index + 1}. ${escapeHtml(fix.name)}</h3><p>${escapeHtml(fix.detail)}</p><p class="muted">${escapeHtml(JSON.stringify(fix.settings))}</p></article>`).join("")}</section>
  <section><h2>Recommended Tools</h2>${plugins.map((plugin) => `<article><span class="tag">${escapeHtml(plugin.type)}</span><h3>${escapeHtml(plugin.name)}</h3><p>${escapeHtml(plugin.reason)}</p><p><strong>Move:</strong> ${escapeHtml(plugin.move)}</p></article>`).join("")}</section>
</main>
</body>
</html>`;
}

function exportProjectSnapshot() {
  if (!currentReport) return;
  const project = {
    app: "Auralyze",
    version: 1,
    exportedAt: new Date().toISOString(),
    report: currentReport,
  };
  const blob = new Blob([JSON.stringify(project, null, 2)], { type: "application/json" });
  downloadBlob(blob, `${safeBaseName(currentReport.projectName || currentReport.fileName)}.auralyze.json`);
}

async function importProjectSnapshot(event) {
  const [file] = event.target.files;
  if (!file) return;
  try {
    const data = JSON.parse(await file.text());
    const report = data.report || data;
    if (!report.metrics || !report.spectral || !report.issues) throw new Error("Invalid Auralyze project");
    const projects = readProjects();
    const id = report.projectId || `project-${Date.now()}`;
    const imported = {
      ...report,
      projectId: id,
      projectName: report.projectName || safeBaseName(file.name),
      importedAt: new Date().toISOString(),
      savedAt: new Date().toISOString(),
    };
    projects[id] = imported;
    writeProjects(projects);
    refreshProjectLibrary(id);
    projectLibrary.value = id;
    loadSelectedProject();
    copilotAnswer.textContent = `Imported "${imported.projectName}" into local project memory.`;
  } catch (error) {
    console.error(error);
    copilotAnswer.textContent = "Import failed. Choose a valid Auralyze project JSON file.";
  } finally {
    projectImport.value = "";
  }
}

async function copyPresetChain() {
  if (!currentReport) return;
  const preset = currentReport.fixes
    .map((step, index) => `${index + 1}. ${step.name}: ${step.detail} ${JSON.stringify(step.settings)}`)
    .join("\n");
  try {
    await navigator.clipboard.writeText(preset);
    copilotAnswer.textContent = "Processing chain copied. Paste it into notes, a DAW session plan, or a plugin preset brief.";
  } catch (error) {
    console.warn(error);
    copilotAnswer.textContent = preset;
  }
}

function resetSession() {
  stopPlayback();
  currentBuffer = null;
  currentReport = null;
  currentStemAnalyses = [];
  currentReference = null;
  audioInput.value = "";
  referenceInput.value = "";
  fileName.textContent = "No file loaded";
  activeMode.textContent = "Waiting for audio";
  summary.textContent = "Upload an audio file to get a plain-English diagnosis with measurable evidence.";
  issueList.innerHTML = "";
  issueCount.textContent = "0 issues";
  fixChain.innerHTML = "<p>No processing chain yet.</p>";
  pluginList.innerHTML = '<p class="empty-note">Recommendations appear after analysis.</p>';
  timelineList.innerHTML = '<p class="empty-note">Upload audio to locate clipping, loudness jumps, harsh moments, and quiet gaps over time.</p>';
  markerCount.textContent = "0 markers";
  maskingList.innerHTML = '<p class="empty-note">Add stems to reveal frequency collisions between parts.</p>';
  conflictCount.textContent = "0 conflicts";
  renderStemAnalysis([]);
  metricList.innerHTML = `
    <div><dt>Peak</dt><dd>-</dd></div>
    <div><dt>True peak</dt><dd>-</dd></div>
    <div><dt>Loudness</dt><dd>-</dd></div>
    <div><dt>Noise floor</dt><dd>-</dd></div>
    <div><dt>Dynamics</dt><dd>-</dd></div>
    <div><dt>Stereo</dt><dd>-</dd></div>
  `;
  projectName.value = "";
  projectLibrary.value = "";
  copilotAnswer.textContent = "Load audio, then ask the copilot for a prioritized fix plan.";
  drawEmptyState();
  setStatus("Ready");
  for (const button of [playOriginalButton, playEnhancedButton, stopButton, exportWavButton, exportHtmlButton, exportReportButton, copyPresetButton, resetSessionButton, saveProjectButton, deleteProjectButton, exportProjectButton, askCopilotButton]) {
    button.disabled = true;
  }
}

function answerCopilotQuestion() {
  if (!currentReport) return;
  const question = copilotQuestion.value.trim().toLowerCase();
  const issues = currentReport.issues.filter((issue) => issue.severity !== "good");
  const topIssue = issues[0];
  const reference = currentReport.referenceComparison;
  const stemConflict = currentReport.stemConflicts[0];
  const knowledge = retrieveKnowledge(question || issues.map((issue) => issue.title).join(" "));

  let answer;
  if (!question || /first|priority|start|begin|fix plan|what should/i.test(question)) {
    answer = withKnowledge(buildPriorityPlan(issues), knowledge);
  } else if (/mud|cloud|boxy|low mid/.test(question)) {
    answer = withKnowledge(explainMuddiness(), knowledge);
  } else if (/vocal|voice|dialog|speech/.test(question)) {
    answer = withKnowledge(explainVocalPlan(stemConflict), knowledge);
  } else if (/bass|kick|low|808|sub/.test(question)) {
    answer = withKnowledge(explainLowEndPlan(), knowledge);
  } else if (/reference|target|match/.test(question) && reference) {
    answer = withKnowledge(explainReferencePlan(reference), knowledge);
  } else if (/plugin|tool|eq|compressor|limiter|recommend/.test(question)) {
    answer = withKnowledge(explainPluginPlan(), knowledge);
  } else if (/master|release|spotify|youtube|club|cinema|podcast|stream/.test(question)) {
    answer = withKnowledge(`<strong>Release target:</strong> ${escapeHtml(targetDescription(currentReport.releaseTarget))} The current chain includes target-specific notes and, where useful, extra EQ or headroom moves.`, knowledge);
  } else if (/export|download|wav|render/.test(question)) {
    answer = "<strong>Export path:</strong> use Export enhanced WAV to render the current preview chain into a downloadable WAV file.";
  } else {
    answer = topIssue
      ? `<strong>Best read:</strong> ${escapeHtml(topIssue.title)}. ${escapeHtml(topIssue.explanation)} <strong>Move:</strong> ${escapeHtml(topIssue.fix)}`
      : "I do not see a major technical fault yet. Compare with a reference track, then listen for vocal level, low-end tightness, and top-end fatigue.";
    answer = withKnowledge(answer, knowledge);
  }

  copilotAnswer.innerHTML = answer;
}

function retrieveKnowledge(query) {
  const words = String(query)
    .toLowerCase()
    .split(/[^a-z0-9-]+/)
    .filter(Boolean);
  const scored = knowledgeBase
    .map((item) => ({
      item,
      score: item.keywords.reduce((total, keyword) => total + (words.includes(keyword) || query.includes(keyword) ? 1 : 0), 0),
    }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score);
  return scored.slice(0, 2).map((entry) => entry.item);
}

function withKnowledge(answer, knowledge) {
  if (!knowledge.length) return answer;
  const notes = knowledge
    .map((item) => `<div><strong>${escapeHtml(item.topic)}:</strong> ${escapeHtml(item.guidance)} <strong>Move:</strong> ${escapeHtml(item.move)}</div>`)
    .join("");
  return `${answer}<div class="knowledge-notes">${notes}</div>`;
}

function setStatus(text) {
  analysisStatus.textContent = text;
}

function buildPriorityPlan(issues) {
  if (!issues.length) {
    return "The file looks technically healthy. Next, compare against a reference and make creative choices by genre, mood, and playback device.";
  }
  return `<strong>Priority plan:</strong> 1. ${escapeHtml(issues[0].fix)} ${issues[1] ? `2. ${escapeHtml(issues[1].fix)}` : ""} ${issues[2] ? `3. ${escapeHtml(issues[2].fix)}` : ""}`;
}

function explainMuddiness() {
  const lowMid = currentReport.spectral.bands.lowMid;
  const presence = currentReport.spectral.bands.presence;
  return `<strong>Mud check:</strong> low-mid energy is ${pct(lowMid)} and presence is ${pct(presence)}. If the audio feels cloudy, cut 220-320 Hz broadly, then add only a small clarity lift around 2-4 kHz. Do the cut before boosting.`;
}

function explainVocalPlan(conflict) {
  const vocal = currentReport.stems.find((stem) => stem.role === "vocal");
  if (!vocal) {
    return "I do not see a dedicated vocal stem yet. Upload a file with vocal, vox, voice, or dialogue in the name to unlock stronger vocal masking analysis.";
  }
  const conflictText = conflict ? ` Strongest detected conflict: ${escapeHtml(conflict.title)}.` : "";
  return `<strong>Vocal plan:</strong> set vocal level first, then remove masking around 2-4 kHz on competing instruments, then use light compression. Vocal loudness is ${formatDb(vocal.metrics.loudnessDb)} RMS.${conflictText}`;
}

function explainLowEndPlan() {
  const kick = currentReport.stems.find((stem) => stem.role === "kick");
  const bass = currentReport.stems.find((stem) => stem.role === "bass");
  if (kick && bass) {
    return `<strong>Low-end plan:</strong> kick is ${formatDb(kick.metrics.loudnessDb)} RMS and bass is ${formatDb(bass.metrics.loudnessDb)} RMS. Pick one owner for 50-80 Hz, sidechain bass gently from kick, and keep stereo widening away from subs.`;
  }
  return "For low end, high-pass non-bass tracks, keep subs mono, and compare kick/bass balance on small speakers and headphones.";
}

function explainReferencePlan(reference) {
  return `<strong>Reference match:</strong> loudness gap is ${formatDb(reference.loudnessGapDb)}, dynamics gap is ${formatDb(reference.dynamicsGapDb)}, and spectral centroid gap is ${Math.round(reference.centroidGapHz)} Hz. Match loudness before judging EQ.`;
}

function explainPluginPlan() {
  const recommendations = buildPluginRecommendations(currentReport.issues, currentReport.fixes, currentReport.stems, currentReport.referenceComparison);
  return `<strong>Plugin plan:</strong> start with ${escapeHtml(recommendations[0].name)} for ${escapeHtml(recommendations[0].reason.toLowerCase())} ${recommendations[1] ? `Then use ${escapeHtml(recommendations[1].name)} if the first move exposes another problem.` : ""}`;
}

function downloadBlob(blob, name) {
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = name;
  link.click();
  URL.revokeObjectURL(link.href);
}

function readProjects() {
  try {
    return JSON.parse(localStorage.getItem(projectStoreKey) || "{}");
  } catch (error) {
    console.warn(error);
    return {};
  }
}

function writeProjects(projects) {
  try {
    localStorage.setItem(projectStoreKey, JSON.stringify(projects));
  } catch (error) {
    console.warn(error);
    copilotAnswer.textContent = "Could not save project locally. Browser storage may be full or disabled.";
  }
}

function refreshProjectLibrary(selectedId = "") {
  const projects = Object.values(readProjects()).sort((a, b) => new Date(b.savedAt || 0) - new Date(a.savedAt || 0));
  if (!projects.length) {
    projectLibrary.innerHTML = '<option value="">No saved projects</option>';
    projectLibrary.value = "";
    deleteProjectButton.disabled = true;
    return;
  }

  projectLibrary.innerHTML = [
    '<option value="">Saved projects</option>',
    ...projects.map((project) => `<option value="${escapeHtml(project.projectId)}">${escapeHtml(project.projectName || project.fileName || "Untitled project")}</option>`),
  ].join("");
  projectLibrary.value = selectedId;
  deleteProjectButton.disabled = !selectedId;
}

function safeBaseName(name) {
  return (name || "audio").replace(/\.[^.]+$/, "").replace(/[^a-z0-9-_]+/gi, "-").replace(/^-|-$/g, "") || "audio";
}

function formatTime(seconds) {
  const safeSeconds = Math.max(0, seconds);
  const minutes = Math.floor(safeSeconds / 60);
  const remainder = Math.floor(safeSeconds % 60);
  return `${minutes}:${String(remainder).padStart(2, "0")}`;
}

function encodeWav(buffer) {
  const channels = buffer.numberOfChannels;
  const sampleRate = buffer.sampleRate;
  const bytesPerSample = 2;
  const blockAlign = channels * bytesPerSample;
  const dataSize = buffer.length * blockAlign;
  const arrayBuffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(arrayBuffer);
  let offset = 0;

  writeString(view, offset, "RIFF");
  offset += 4;
  view.setUint32(offset, 36 + dataSize, true);
  offset += 4;
  writeString(view, offset, "WAVE");
  offset += 4;
  writeString(view, offset, "fmt ");
  offset += 4;
  view.setUint32(offset, 16, true);
  offset += 4;
  view.setUint16(offset, 1, true);
  offset += 2;
  view.setUint16(offset, channels, true);
  offset += 2;
  view.setUint32(offset, sampleRate, true);
  offset += 4;
  view.setUint32(offset, sampleRate * blockAlign, true);
  offset += 4;
  view.setUint16(offset, blockAlign, true);
  offset += 2;
  view.setUint16(offset, bytesPerSample * 8, true);
  offset += 2;
  writeString(view, offset, "data");
  offset += 4;
  view.setUint32(offset, dataSize, true);
  offset += 4;

  const channelData = Array.from({ length: channels }, (_, channel) => buffer.getChannelData(channel));
  for (let i = 0; i < buffer.length; i += 1) {
    for (let channel = 0; channel < channels; channel += 1) {
      const sample = clamp(channelData[channel][i], -1, 1);
      view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
      offset += 2;
    }
  }

  return new Blob([arrayBuffer], { type: "audio/wav" });
}

function writeString(view, offset, value) {
  for (let i = 0; i < value.length; i += 1) view.setUint8(offset + i, value.charCodeAt(i));
}

function average(values) {
  return values.reduce((total, value) => total + value, 0) / Math.max(values.length, 1);
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function fft(real, imag) {
  const n = real.length;
  for (let i = 1, j = 0; i < n; i += 1) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      [real[i], real[j]] = [real[j], real[i]];
      [imag[i], imag[j]] = [imag[j], imag[i]];
    }
  }

  for (let len = 2; len <= n; len <<= 1) {
    const angle = (-2 * Math.PI) / len;
    const wLenReal = Math.cos(angle);
    const wLenImag = Math.sin(angle);
    for (let i = 0; i < n; i += len) {
      let wReal = 1;
      let wImag = 0;
      for (let j = 0; j < len / 2; j += 1) {
        const evenReal = real[i + j];
        const evenImag = imag[i + j];
        const oddReal = real[i + j + len / 2] * wReal - imag[i + j + len / 2] * wImag;
        const oddImag = real[i + j + len / 2] * wImag + imag[i + j + len / 2] * wReal;

        real[i + j] = evenReal + oddReal;
        imag[i + j] = evenImag + oddImag;
        real[i + j + len / 2] = evenReal - oddReal;
        imag[i + j + len / 2] = evenImag - oddImag;

        const nextReal = wReal * wLenReal - wImag * wLenImag;
        wImag = wReal * wLenImag + wImag * wLenReal;
        wReal = nextReal;
      }
    }
  }
}
