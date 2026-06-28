# Auralyze Backend Scaffold

Dependency-free local backend scaffold for the product features that need a service layer.

## Run

```powershell
python backend/server.py
```

Default URL: `http://127.0.0.1:8788`

## Routes

- `GET /health`
- `GET /api/ai/status`
- `GET /api/projects`
- `POST /api/projects`
- `GET /api/knowledge/search?q=vocal`
- `POST /api/copilot`
- `POST /api/knowledge/documents`
- `GET /api/knowledge/documents`
- `POST /api/accounts/local-login`
- `POST /api/stem-separation/jobs`
- `POST /api/plugin-presets`
- `POST /api/format/inspect`
- `GET /api/audio/status`
- `POST /api/audio/transcode`
- `GET /api/storage/status`
- `GET /api/storage/export`
- `GET /api/auth/status`
- `GET /api/auth/me`

## Free Local Copilot

The default copilot path is free:

- If Ollama is running with `OLLAMA_MODEL`, the backend asks the local model.
- If Ollama is not installed or the model is missing, the route still answers with deterministic DSP/OKF rules.
- No paid API key is required.

Recommended `.env`:

```text
AI_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2:3b
```

To use the local LLM layer, install Ollama and run:

```powershell
ollama pull llama3.2:3b
scripts\check_local_ai.cmd
python backend/server.py
```

## OKF/RAG Knowledge

The backend retrieves from:

- built-in production notes
- structured OKF files in `backend/knowledge/*.okf.json`
- markdown files in `backend/knowledge/*.md`
- notes saved through `POST /api/knowledge/documents`

The Flutter app has an **OKF/RAG knowledge** panel where you can add a title, tags, and reference text. Later copilot questions retrieve matching chunks and pass them into the local model or rule-based answer builder.

OKF files are local JSON knowledge files. They are useful when you want explainable retrieval without a vector database:

```json
{
  "schema": "auralyze-okf-v1",
  "title": "Audio Knowledge",
  "entries": [
    {
      "id": "muddy-vocal",
      "title": "Muddy Vocal",
      "symptoms": ["vocal sounds muddy"],
      "causes": ["too much 180 Hz to 350 Hz energy"],
      "fixes": ["cut competing instruments around 220 Hz to 320 Hz"],
      "tools": ["EQ", "dynamic EQ"],
      "tags": ["vocal", "muddy", "clarity"]
    }
  ]
}
```

Run `scripts\check_okf.cmd` from the project root to inspect the local OKF/RAG index.

## Free Storage

Projects, local accounts, and user-added RAG notes can use local JSON files or a local SQLite file. No paid database is required.

```text
AURALYZE_STORAGE=json
```

or:

```text
AURALYZE_STORAGE=sqlite
```

Check the active backend with:

```cmd
scripts\check_storage.cmd
```

The backend also exposes `GET /api/storage/status` and `GET /api/storage/export`.

For free hosted persistence, set:

```text
AURALYZE_STORAGE=postgres
DATABASE_URL=postgresql://user:password@host/dbname?sslmode=require
```

The Postgres adapter is compatible with Neon and Supabase free Postgres URLs.

## Free Hosted Auth

Local demo auth stays enabled by default. To verify hosted JWTs, install `requirements.txt` and set Clerk or Firebase environment variables:

```text
AURALYZE_AUTH_PROVIDER=clerk
CLERK_ISSUER=https://your-clerk-domain.clerk.accounts.dev
AURALYZE_REQUIRE_AUTH=true
```

or:

```text
AURALYZE_AUTH_PROVIDER=firebase
FIREBASE_PROJECT_ID=your-firebase-project-id
AURALYZE_REQUIRE_AUTH=true
```

When `AURALYZE_REQUIRE_AUTH=true`, project and custom-knowledge writes require `Authorization: Bearer <token>`.

## OKF MCP Server

The OKF knowledge layer is also available as a dependency-free MCP stdio server:

```powershell
python backend/okf_mcp_server.py
```

From the project root, use:

```cmd
scripts\start_okf_mcp.cmd
scripts\check_okf_mcp.cmd
```

Exposed tools:

- `okf.search`
- `okf.answer`
- `okf.documents`

Exposed resources:

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

## MP3/M4A/FLAC Support

WAV works natively in the Flutter app. MP3, M4A, AAC, FLAC, and OGG use FFmpeg through the backend:

```powershell
scripts\check_ffmpeg.cmd
```

If FFmpeg is not on PATH, set `FFMPEG_PATH` in `.env`:

```text
FFMPEG_PATH=C:\ffmpeg\bin\ffmpeg.exe
```

The app's **System status** panel shows whether compressed-format upload is active.

## Free Stem Fallback

When Demucs is installed, `/api/stem-separation/separate` uses Demucs for true neural source separation. When Demucs is not installed but FFmpeg is available, the same route returns approximate frequency-shaped stems for vocals, drums, bass, and other. This keeps free hosted deployments useful without GPU-heavy dependencies.

The fallback is not a replacement for Demucs quality. It is a practical demo/diagnosis path for Render Free and similar hosts.

## Notes

This is a local backend foundation. Team sync, production auth, or optional commercial providers can be added behind this API surface instead of being hard-coded into the Flutter app.
