# Auralyze

Auralyze is an early prototype for an AI Audio Diagnosis Copilot: a browser-based tool that listens to an audio file, finds common technical mix problems, explains them in plain English, and creates a reversible enhanced preview chain.

## Current MVP

- Local audio upload and browser-side decoding
- Multi-stem upload with automatic role guesses from filename and spectral clues
- Single-song source separation through the backend Demucs engine when installed
- Waveform and spectrum visualization
- Peak, RMS loudness, dynamics, stereo balance, phase correlation, clipping, DC offset, and frequency-band analysis
- Approximate LUFS, true-peak estimate, noise floor, and timeline problem markers
- Plain-English diagnosis for muddiness, harshness, low-end buildup, phase risk, clipping, and dynamics issues
- Stem conflict detection for vocal masking, kick/bass collisions, and brightness buildup
- Suggested processing chain with original/enhanced preview playback
- Enhanced WAV export rendered from the preview chain
- Repaired WAV preview/export for click smoothing, DC cleanup, noise-gate cleanup, and soft limiting
- Reference-track comparison for loudness, dynamics, and spectral balance gaps
- Real reference-track matching in Flutter with uploaded reference audio, match score, LUFS/dynamics/true-peak deltas, and fix actions
- Release target profiles for balanced, streaming, YouTube, club, cinema, and podcast output
- Plugin-style recommendations for EQ, compression, limiting, stereo control, low-end shaping, and reference matching
- Copyable processing-chain preset notes
- DAW-neutral processing preset JSON export with ordered processors and suggested parameter values
- REAPER ReaScript export that inserts Cockos helper FX and stores the Auralyze chain on the selected track
- Prompt-to-sound generator that synthesizes playable/exportable WAV effects locally
- Built-in production copilot Q&A over the current analysis with a local mixing knowledge base
- Local project memory for saving, loading, and deleting analysis snapshots
- Backend-backed local account, plan activation, and cloud-project save/load/delete workflow
- Free JSON or SQLite persistence for projects, accounts, and custom knowledge
- Import/export `.auralyze.json` project snapshots
- Client-ready self-contained HTML report export
- JSON report export

## How to Run

Open `index.html` in a browser, or serve the folder with any static file server.

## Smoke Test

Run `node scripts/smoke-test.js` from the project root to exercise the analyzer with synthetic stems.

## Product Direction

The first product should stay focused on one question:

> Why does my audio sound bad, and what should I do next?

Future layers:

- LLM explanations and RAG over trusted mixing/mastering references
- Stem-aware masking analysis
- Before/after rendered exports
- Plugin preset generation
- REAPER or VST/CLAP automation
- Reference-track comparison
- Processed WAV rendering and reference matching

## Flutter App

A Flutter product UI is available in `auralyze_app/`.

Useful commands:

- `flutter pub get`
- `flutter analyze`
- `flutter build web`
- `dart run tool/analysis_smoke.dart`

To run the real local product:

- `flutter build web`
- copy `.env.example` to `.env`
- `scripts\start_product.cmd`
- open `http://127.0.0.1:8791/index.html`

Use the **System status** panel inside the app to confirm:

- backend is online
- AI copilot is using a free local LLM or local DSP/OKF rules
- OKF/RAG knowledge documents are loaded
- FFmpeg format support is active or WAV-only
- Demucs stem separation is ready or needs installation
- storage is using free JSON files or free SQLite

## Free Local AI Setup

Auralyze is free by default. It uses:

- local DSP analysis in Flutter
- local OKF/RAG knowledge in the backend
- Demucs for open-source stem separation
- FFmpeg for open-source format conversion
- Ollama for optional open-source local LLM answers

To enable the local LLM layer:

1. Install Ollama from `https://ollama.com`.
2. Pull a small local model:

```cmd
ollama pull llama3.2:3b
```

3. Keep this in `.env`:

```text
AI_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2:3b
```

4. Run `scripts\check_local_ai.cmd`.
5. Run `scripts\start_product.cmd`.
6. In the app, press **Refresh status**. AI copilot should show `Free local LLM ready`.

If Ollama is not installed, the copilot still works with local DSP/OKF rules.

Never commit `.env`; it is ignored by git.

## Free Local Storage

Auralyze does not require Firebase, Supabase, Postgres, or any paid database. Set this in `.env`:

```text
AURALYZE_STORAGE=json
```

Use `json` for simple local files, or switch to one local SQLite database file:

```text
AURALYZE_STORAGE=sqlite
```

Check it with:

```cmd
scripts\check_storage.cmd
```

The app's **System status** panel shows the active storage backend and current project/knowledge counts.

## FFmpeg Setup For MP3/M4A/FLAC

WAV upload works without FFmpeg. MP3, M4A, AAC, FLAC, OGG, and source separation need FFmpeg:

1. Install FFmpeg for Windows.
2. Either add `ffmpeg.exe` to PATH, or set this in `.env`:

```text
FFMPEG_PATH=C:\ffmpeg\bin\ffmpeg.exe
```

3. Run:

```cmd
scripts\check_ffmpeg.cmd
```

4. Restart `scripts\start_product.cmd`.

## Source Separation Setup

Real one-song-to-stems separation uses Demucs on the backend. WAV files can be separated with Demucs alone; MP3, M4A, AAC, FLAC, and OGG also need FFmpeg.

1. Run:

```cmd
scripts\install_separation.cmd
scripts\check_separation.cmd
```

2. Optional but recommended: install FFmpeg using the section above for MP3/M4A/FLAC/OGG separation.

3. Restart:

```cmd
scripts\start_product.cmd
```

4. In the app, press **Refresh status**. Stem separation should show `Demucs ready` or `Demucs ready - WAV only`.

5. Use **Separate one song** to upload a full mix. Auralyze separates vocals, drums, bass, and other, then feeds those stems into the existing analyzer.

The first separation can be slow because Demucs/PyTorch may download model weights and CPU separation is heavy. For testing, start with a short audio file.

The current Flutter version includes a Dart analyzer in `auralyze_app/lib/audio_analysis.dart` and a WAV decoder in `auralyze_app/lib/wav_decoder.dart`. It can run generated demo stems or import real WAV files through the Flutter file picker, then compute metrics, spectrum, timeline markers, stem conflicts, processing steps, and plugin recommendations.

It also supports WAV export, self-contained HTML report export, JSON project export/import, local copilot answers, and copyable processing-chain notes.

Real local workflow now includes:

- WAV upload and analysis
- single-song source separation through Demucs when installed
- original/enhanced A/B playback in Flutter
- enhanced preview rendering with high-pass cleanup, adaptive EQ, compression, saturation, harshness control, and limiting
- selected preview WAV export
- repaired preview playback and repaired WAV export
- before/after peak comparison
- reference-track matching against uploaded audio, including loudness, dynamics, true-peak, and seven-band tonal-balance gaps
- actionable mastering target rendering: Spotify/streaming, YouTube, club, podcast, and cinema targets rerender the current uploaded or demo audio instead of acting as labels
- processing preset export for the active diagnosis chain
- REAPER script export for the active processing chain
- prompt-to-sound generation with playable/exportable WAV output
- free local AI copilot backend integration through Ollama when installed
- deterministic local DSP/OKF copilot fallback when no model is installed
- real local OKF/RAG retrieval from structured `.okf.json` files, built-in notes, markdown files, and user-added references
- storage status, backup export endpoint, and free SQLite persistence option
- copilot context includes the active reference-match findings when a reference file is loaded
- local account sign-in, local Pro plan activation, and backend project sync

Additional product surfaces include:

- original/enhanced A/B render selection
- enhanced preview WAV rendering
- prompt-to-processing sound designer
- prompt-to-sound generator for lasers, impacts, rain/ambience, risers, drones, and vocal textures
- mastering target variants for streaming, club, podcast, cinema, and YouTube with one-click apply and WAV export
- arrangement suggestions from timeline and stem conflicts
- audio repair checklist
- real audio repair render/export controls
- semantic sample search prototype
- production integration status for LLM, RAG, cloud projects, stem separation, formats, and DAW/plugin automation
- REAPER helper script export for DAW handoff
- app-side knowledge entry panel for adding custom copilot references
- deployment package script plus Windows/Android build helper scripts

## OKF Knowledge Files

Auralyze does not need a vector database. It can retrieve from local **Open Knowledge Files** in `backend/knowledge/*.okf.json`.

Each OKF entry can define:

- `title`
- `symptoms`
- `causes`
- `fixes`
- `tools`
- `tags`

Run:

```cmd
scripts\check_okf.cmd
```

The seed file is `backend/knowledge/audio_production.okf.json`.

## OKF MCP Server

Auralyze also exposes OKF through a dependency-free MCP stdio server:

```cmd
scripts\start_okf_mcp.cmd
```

Smoke test:

```cmd
scripts\check_okf_mcp.cmd
```

MCP tools:

- `okf.search` - search local OKF/RAG knowledge
- `okf.answer` - produce a deterministic OKF answer with sources
- `okf.documents` - list OKF, markdown, and stored knowledge documents

MCP resources:

- `okf://knowledge/index`
- `okf://knowledge/documents`
- `okf://file/...`
- `okf://entry/...`
- `okf://search/{query}`

Example MCP client config:

```json
{
  "mcpServers": {
    "auralyze-okf": {
      "command": "python",
      "args": [
        "C:\\Users\\Chandu\\OneDrive\\Dokumen\\SoundMesh\\backend\\okf_mcp_server.py"
      ]
    }
  }
}
```

## Backend Scaffold

A dependency-free local backend is available in `backend/` for product features that should eventually move out of the client:

- project save/list/load/delete API
- local copilot API
- OKF/RAG knowledge search API
- OKF MCP stdio server
- AI provider status endpoint
- local account bootstrap API
- free local plan activation API
- RAG document ingestion API
- storage status/export API
- mastering target API
- stem separation job scaffold
- format inspection scaffold
- plugin preset scaffold

Run it with:

- `python backend/server.py`

Default URL: `http://127.0.0.1:8788`

The default AI provider is Ollama. If Ollama is unavailable, the copilot automatically falls back to local DSP/OKF rules. Optional paid providers can be added later behind the same API surface without changing the Flutter app.

Project, account, and user-added knowledge storage is free by default. Use `AURALYZE_STORAGE=json` for local JSON files or `AURALYZE_STORAGE=sqlite` for a local SQLite file.

## Packaging And App Builds

Create a portable local product bundle:

```cmd
scripts\package_product.cmd
```

Build platform targets:

```cmd
scripts\build_desktop.cmd
scripts\build_android.cmd
```

See `deployment.md` for production environment variables and hosting notes.

## Deploy

The repo includes a single-container deployment path:

- [Dockerfile](C:/Users/Chandu/OneDrive/Dokumen/SoundMesh/Dockerfile)
- [render.yaml](C:/Users/Chandu/OneDrive/Dokumen/SoundMesh/render.yaml)
- [deployment.md](C:/Users/Chandu/OneDrive/Dokumen/SoundMesh/deployment.md)

The container builds Flutter web and serves both the app and backend from one port. Public demo deployments default to `AI_PROVIDER=local-rules`; use your own PC/VPS if you want hosted Ollama + Demucs.

The repo also includes a free GitHub Pages workflow at `.github/workflows/pages.yml`. It publishes the Flutter web demo from `main`; backend-only features will show offline until you connect a hosted backend URL through the `AURALYZE_BACKEND_URL` repository variable.

Free repository checks are available in `.github/workflows/ci.yml`; it runs backend checks, OKF/MCP smoke tests, storage checks, Flutter analyze/tests, and a web build.
