# Auralyze Deployment Notes

## Recommended Deployment Shape

The easiest public deployment is the **single-container web app**:

- Flutter web is built into static files.
- The Python backend serves both the static app and `/api/...` routes.
- The app uses same-origin API calls, so no public backend URL has to be hard-coded.
- The deployed container defaults to `AI_PROVIDER=local-rules` because free cloud containers usually do not have enough memory/storage for Ollama and Demucs.
- Public free deploys use an FFmpeg spectral stem fallback when Demucs is not installed.

Use this for demos, submissions, and portfolio links.

Use your own PC/VPS for the full heavy version with:

- Ollama local LLM
- Demucs source separation
- FFmpeg
- OKF MCP server

## Docker Deployment

Build:

```cmd
docker build -t auralyze .
```

Run:

```cmd
docker run --rm -p 8080:8080 auralyze
```

Open:

```text
http://127.0.0.1:8080
```

The Docker image listens on `$PORT` and binds to `0.0.0.0`, so it works on Docker-based hosts.

Default Docker environment:

```text
AI_PROVIDER=local-rules
AURALYZE_WEB_DIR=/app/web
AURALYZE_STORAGE=sqlite
AURALYZE_FALLBACK_MAX_SECONDS=180
PORT=8080
```

If you have a separate Ollama server reachable from the container, set:

```text
AI_PROVIDER=ollama
OLLAMA_URL=https://your-ollama-host
OLLAMA_MODEL=llama3.2:3b
```

## Render Blueprint

`render.yaml` is included for a Docker web service. Connect the repo to Render and create the service from the blueprint. The service uses:

```text
runtime: docker
dockerfilePath: ./Dockerfile
AI_PROVIDER=local-rules
AURALYZE_STORAGE=sqlite
plan=free
```

This gives you a public demo with the Flutter UI, OKF/RAG copilot fallback, project APIs, FFmpeg-backed format support, FFmpeg stem fallback, reports, exports, and free SQLite storage. Free web hosts may use ephemeral disks, so use `/api/storage/export` before rebuilding if you need to keep demo data. Ollama/Demucs should be self-hosted or moved to a bigger worker later.

Render deployment uses `plan: free` in `render.yaml`. Render's own docs say web services can run on Free instances, and its Blueprint reference says omitting `plan` makes a new service use `starter`, so keep `plan: free` in place for no-cost deployment.

## Local Product Package

Run:

```cmd
scripts\package_product.cmd
```

Output:

```text
dist\auralyze_product
```

Start it with:

```cmd
dist\auralyze_product\start_auralyze.cmd
```

## Free Local Environment

The local product can run without paid secrets:

```text
AI_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2:3b
FFMPEG_PATH=...
DEMUCS_COMMAND=python -m demucs
DEMUCS_MODEL=htdemucs
AURALYZE_STORAGE=sqlite
AURALYZE_FALLBACK_MAX_SECONDS=180
```

If Ollama is not installed, Auralyze still uses local DSP/OKF rules. Optional commercial providers such as hosted LLMs or checkout can be added later, but they are not required for this project.

Knowledge retrieval is local. Ship structured OKF files in `backend/knowledge/*.okf.json`, markdown references in `backend/knowledge/*.md`, or user-added notes in JSON/SQLite storage.

The OKF MCP server is local stdio only. Ship `backend/okf_mcp_server.py` with the package and register it in your MCP client using `python backend/okf_mcp_server.py`.

## Frontend-Only Static Hosting

If you deploy only the Flutter web build to GitHub Pages/Netlify/Vercel, build with the deployed backend URL:

```cmd
set AURALYZE_BACKEND_URL=https://your-backend.example.com
scripts\build_web_deploy.cmd
```

Then upload `auralyze_app\build\web`.

For single-container Docker deployment, leave `AURALYZE_BACKEND_URL` empty so the app uses same-origin `/api/...`.

If you enable Firebase login on a static frontend build, pass these build variables too:

```cmd
set AURALYZE_AUTH_MODE=firebase
set AURALYZE_FIREBASE_API_KEY=your-firebase-web-api-key
set AURALYZE_FIREBASE_PROJECT_ID=your-firebase-project-id
```

## Production Notes

The backend supports free JSON or SQLite persistence. On free cloud hosts, local disk may be reset during redeploys, so use `/api/storage/export` for backup or move only long-term shared/team data to a managed database later.

For a free persistent hosted database, use Neon or Supabase Postgres:

```text
AURALYZE_STORAGE=postgres
DATABASE_URL=postgresql://user:password@host/dbname?sslmode=require
```

For free hosted identity, use Clerk or Firebase. Firebase Email/Password is the easiest free path for this app: enable Email/Password in Firebase Authentication, copy the Web API key into the frontend build variables above, and set the backend variables below on Render:

```text
AURALYZE_AUTH_PROVIDER=firebase
FIREBASE_PROJECT_ID=your-firebase-project-id
AURALYZE_REQUIRE_AUTH=true
```

For Clerk instead:

```text
AURALYZE_AUTH_PROVIDER=clerk
CLERK_ISSUER=https://your-clerk-domain.clerk.accounts.dev
AURALYZE_REQUIRE_AUTH=true
```

Demucs is CPU-heavy. The deployed free backend uses an approximate FFmpeg fallback. For clean hosted source separation, run Demucs on a worker machine or queue service rather than inside the web request process.
