const fs = require("fs");
const vm = require("vm");

const elements = new Map();

function makeContext(canvas) {
  return {
    canvas,
    clearRect() {},
    fillRect() {},
    beginPath() {},
    moveTo() {},
    lineTo() {},
    stroke() {},
    fillText() {},
    set fillStyle(value) {},
    set strokeStyle(value) {},
    set lineWidth(value) {},
    set font(value) {},
    set textAlign(value) {},
  };
}

function el(selector) {
  if (!elements.has(selector)) {
    const element = {
      selector,
      textContent: "",
      innerHTML: "",
      disabled: false,
      value: selector === "#releaseTarget" ? "streaming" : "",
      style: {},
      classList: { add() {}, remove() {} },
      addEventListener() {},
      width: 1200,
      height: selector === "#spectrumCanvas" ? 220 : 260,
    };
    element.getContext = () => makeContext(element);
    elements.set(selector, element);
  }
  return elements.get(selector);
}

const buttonEls = [
  "#exportWav",
  "#exportHtml",
  "#exportReport",
  "#playOriginal",
  "#playEnhanced",
  "#stopPlayback",
  "#copyPreset",
  "#resetSession",
  "#saveProject",
  "#deleteProject",
  "#exportProject",
  "#askCopilot",
].map(el);

const context = {
  console,
  Math,
  Date,
  Float32Array,
  Float64Array,
  Array,
  Object,
  JSON,
  RegExp,
  Set,
  Map,
  Blob: class Blob {
    constructor(parts, options) {
      this.parts = parts;
      this.options = options;
    }
  },
  URL: {
    createObjectURL() {
      return "blob:test";
    },
    revokeObjectURL() {},
  },
  navigator: { clipboard: { writeText: async () => {} } },
  localStorage: {
    store: {},
    getItem(key) {
      return this.store[key] || null;
    },
    setItem(key, value) {
      this.store[key] = value;
    },
  },
  crypto: { randomUUID: () => "test-id" },
  document: {
    querySelector: el,
    querySelectorAll(selector) {
      if (selector === "button") return buttonEls;
      if (selector === "canvas") return [el("#waveformCanvas"), el("#spectrumCanvas")];
      return [];
    },
    createElement() {
      return { click() {}, href: "", download: "" };
    },
  },
  AudioContext: function AudioContext() {},
  OfflineAudioContext: function OfflineAudioContext() {},
};

vm.createContext(context);
vm.runInContext(fs.readFileSync("app.js", "utf8"), context);

const sampleRate = 44100;
const length = sampleRate;

function fakeBuffer(freqs, gain) {
  const data = new Float32Array(length);
  for (let i = 0; i < length; i += 1) {
    const t = i / sampleRate;
    data[i] =
      (freqs.reduce((sum, freq) => sum + Math.sin(2 * Math.PI * freq * t), 0) * gain) /
      freqs.length;
  }
  return {
    duration: 1,
    length,
    numberOfChannels: 1,
    sampleRate,
    getChannelData() {
      return data;
    },
  };
}

const stems = [
  context.analyzeStem({ name: "vocal-test.wav" }, fakeBuffer([260, 3200], 0.45)),
  context.analyzeStem({ name: "guitar-test.wav" }, fakeBuffer([250, 3000], 0.5)),
  context.analyzeStem({ name: "kick-test.wav" }, fakeBuffer([55, 80], 0.65)),
  context.analyzeStem({ name: "bass-test.wav" }, fakeBuffer([55, 95], 0.55)),
];

context.runAnalysis(fakeBuffer([260, 3200], 0.45), stems);
el("#projectName").value = "Smoke Test Session";
context.saveProjectSnapshot();
el("#copilotQuestion").value = "why are vocals muddy";
context.answerCopilotQuestion();
const savedProjects = JSON.parse(context.localStorage.getItem("auralyze.projects.v1"));
const savedReport = Object.values(savedProjects)[0];
const htmlReport = context.buildHtmlReport(savedReport);

const result = {
  stemCount: el("#stemCount").textContent,
  conflictCount: el("#conflictCount").textContent,
  issueCount: el("#issueCount").textContent,
  hasIssues: el("#issueList").innerHTML.includes("issue-card"),
  hasConflicts: el("#maskingList").innerHTML.includes("mask-row"),
  hasFixes: el("#fixChain").innerHTML.includes("fix-step"),
  hasPlugins: el("#pluginList").innerHTML.includes("plugin-card"),
  hasTimeline: el("#timelineList").innerHTML.includes("timeline-row") || el("#markerCount").textContent === "0 markers",
  hasSavedProject: el("#projectLibrary").innerHTML.includes("Smoke Test Session"),
  hasKnowledge: el("#copilotAnswer").innerHTML.includes("knowledge-notes"),
  hasHtmlReport: htmlReport.includes("Auralyze audio diagnosis report") && htmlReport.includes("Processing Chain"),
};

console.log(JSON.stringify(result, null, 2));

if (
  !result.hasIssues ||
  !result.hasConflicts ||
  !result.hasFixes ||
  !result.hasPlugins ||
  !result.hasTimeline ||
  !result.hasSavedProject ||
  !result.hasKnowledge ||
  !result.hasHtmlReport
) {
  process.exitCode = 1;
}
