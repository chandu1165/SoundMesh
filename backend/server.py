from __future__ import annotations

import json
import mimetypes
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import base64
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse
from uuid import uuid4


ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parent
DATA_DIR = ROOT / "data"
KNOWLEDGE_DIR = ROOT / "knowledge"
PROJECTS_FILE = DATA_DIR / "projects.json"
ACCOUNTS_FILE = DATA_DIR / "accounts.json"
KNOWLEDGE_FILE = DATA_DIR / "knowledge.json"
SQLITE_FILE = DATA_DIR / "auralyze.sqlite3"

KNOWLEDGE = [
    {
        "topic": "Muddiness",
        "keywords": ["mud", "muddy", "cloudy", "boxy", "low mid", "250", "300"],
        "guidance": "Reduce masking in the 150-350 Hz body range before boosting clarity.",
        "move": "Cut competing instruments around 220-320 Hz with a broad dynamic EQ.",
    },
    {
        "topic": "Vocal clarity",
        "keywords": ["vocal", "voice", "dialog", "speech", "presence"],
        "guidance": "Vocal intelligibility depends on level, 2-5 kHz presence, and reduced masking.",
        "move": "Set level first, carve pockets in guitars/keys, then compress and de-ess.",
    },
    {
        "topic": "Kick and bass",
        "keywords": ["kick", "bass", "808", "sub", "low end"],
        "guidance": "Kick and bass need separate ownership in the sub and bass ranges.",
        "move": "Choose one owner for 50-80 Hz and sidechain bass lightly from kick.",
    },
    {
        "topic": "Reference matching",
        "keywords": ["reference", "target", "master", "spotify", "youtube"],
        "guidance": "Reference comparison is useful only after loudness matching.",
        "move": "Match perceived loudness before judging EQ, width, or punch.",
    },
]


def load_dotenv() -> None:
    env_file = WORKSPACE / ".env"
    if not env_file.exists():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def ffmpeg_path() -> str | None:
    configured = os.environ.get("FFMPEG_PATH")
    if configured:
        configured_file = Path(configured)
        try:
            if configured_file.exists():
                return str(configured_file)
        except PermissionError:
            return configured
        except OSError:
            pass
        if can_run_command([configured, "-version"]):
            return str(configured_file)
        found = shutil.which(configured)
        if found:
            return found
    found = shutil.which("ffmpeg")
    if found:
        return found
    for python in python_candidates():
        try:
            result = subprocess.run(
                [
                    python,
                    "-c",
                    "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())",
                ],
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            if result.returncode == 0:
                candidate = result.stdout.strip()
                if candidate and Path(candidate).exists():
                    return candidate
        except Exception:
            continue
    return None


def can_run_command(command: list[str]) -> bool:
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        return result.returncode == 0
    except Exception:
        return False


def demucs_command() -> list[str] | None:
    configured = os.environ.get("DEMUCS_COMMAND")
    if configured:
        command = configured.split()
        if can_run_command([*command, "--help"]):
            return command
        return None
    found = shutil.which("demucs")
    if found:
        return [found]
    for python in python_candidates():
        try:
            result = subprocess.run(
                [python, "-m", "demucs", "--help"],
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            if result.returncode == 0:
                return [python, "-m", "demucs"]
        except Exception:
            continue
    return None


def python_candidates() -> list[str]:
    candidates = [sys.executable]
    found = shutil.which("python")
    if found:
        candidates.append(found)
    local_python = Path.home() / "AppData" / "Local" / "Python"
    if local_python.exists():
        candidates.extend(
            str(path)
            for path in sorted(local_python.glob("pythoncore-*/python.exe"))
        )
    seen = set()
    unique = []
    for candidate in candidates:
        if candidate not in seen and Path(candidate).exists():
            seen.add(candidate)
            unique.append(candidate)
    return unique


class AuralyzeHandler(BaseHTTPRequestHandler):
    server_version = "AuralyzeBackend/0.1"

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.add_cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json({"ok": True, "service": "auralyze-backend"})
            return
        if parsed.path == "/api/ai/status":
            self.send_json(ai_status())
            return
        if parsed.path == "/api/auth/status":
            self.send_json(auth_status())
            return
        if parsed.path == "/api/auth/me":
            try:
                user = verify_bearer_token(self.headers.get("authorization"))
                self.send_json({"authenticated": True, "user": user})
            except ValueError as error:
                status = 401 if auth_required() else 200
                self.send_json(
                    {
                        "authenticated": False,
                        "provider": auth_provider(),
                        "error": str(error),
                    },
                    status=status,
                )
            return
        if parsed.path == "/api/audio/status":
            self.send_json(
                {
                    "ffmpegAvailable": ffmpeg_path() is not None,
                    "ffmpegPath": ffmpeg_path(),
                    "nativeFormats": ["wav"],
                    "transcodeFormats": ["mp3", "m4a", "aac", "flac", "ogg"],
                }
            )
            return
        if parsed.path == "/api/stem-separation/status":
            command = demucs_command()
            has_ffmpeg = ffmpeg_path() is not None
            fallback_available = has_ffmpeg
            engine = "Demucs" if command else "FFmpeg spectral fallback"
            self.send_json(
                {
                    "available": command is not None or fallback_available,
                    "engine": engine if has_ffmpeg or command else "Unavailable",
                    "mode": "demucs" if command else "ffmpeg-fallback"
                    if fallback_available
                    else "unavailable",
                    "command": " ".join(command) if command else None,
                    "ffmpegAvailable": has_ffmpeg,
                    "fallbackAvailable": fallback_available,
                    "fallbackEngine": "FFmpeg spectral fallback"
                    if fallback_available
                    else None,
                    "quality": "pro-model" if command else "approximate-band-split"
                    if fallback_available
                    else "unavailable",
                    "supportedFormats": ["wav", "mp3", "m4a", "aac", "flac", "ogg"]
                    if has_ffmpeg
                    else ["wav"],
                    "expectedStems": ["vocals", "drums", "bass", "other"],
                    "installHint": "Demucs gives cleaner true source separation. FFmpeg fallback is available for free hosted demos."
                    if fallback_available and command is None
                    else "Install Demucs for best separation. Install FFmpeg too for MP3/M4A/FLAC/OGG.",
                }
            )
            return
        if parsed.path == "/api/projects":
            if not self.ensure_auth_if_required():
                return
            self.send_json({"projects": list(read_projects().values())})
            return
        project_match = re.fullmatch(r"/api/projects/(?P<project_id>[^/]+)", parsed.path)
        if project_match:
            if not self.ensure_auth_if_required():
                return
            project = read_projects().get(project_match.group("project_id"))
            if project is None:
                self.send_json({"error": "Project not found"}, status=404)
                return
            self.send_json({"project": project})
            return
        if parsed.path == "/api/billing/status":
            self.send_json(
                {
                    "stripeConfigured": bool(os.environ.get("STRIPE_SECRET_KEY")),
                    "mode": "stripe-ready"
                    if os.environ.get("STRIPE_SECRET_KEY")
                    else "local-demo",
                    "plans": billing_plans(),
                }
            )
            return
        if parsed.path == "/api/storage/status":
            self.send_json(storage_status())
            return
        if parsed.path == "/api/storage/export":
            self.send_json(
                {
                    "exportedAt": iso_now(),
                    "storage": storage_status(),
                    "projects": read_projects(),
                    "accounts": read_accounts(),
                    "knowledge": read_knowledge_documents(),
                    "documents": list_knowledge_documents(),
                }
            )
            return
        if parsed.path == "/api/features":
            self.send_json({"features": product_features()})
            return
        if parsed.path == "/api/mastering/targets":
            self.send_json({"targets": mastering_targets()})
            return
        if parsed.path == "/api/knowledge/search":
            query = parse_qs(parsed.query).get("q", [""])[0]
            self.send_json({"results": search_knowledge(query)})
            return
        if parsed.path == "/api/knowledge/documents":
            self.send_json({"documents": list_knowledge_documents()})
            return
        if not parsed.path.startswith("/api/") and self.serve_static(parsed.path):
            return
        self.send_error(404, "Route not found")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/audio/transcode":
            self.handle_audio_transcode()
            return
        if parsed.path == "/api/stem-separation/separate":
            self.handle_stem_separation()
            return
        body = self.read_body()
        if parsed.path == "/api/projects":
            if not self.ensure_auth_if_required():
                return
            projects = read_projects()
            project_id = body.get("id") or str(uuid4())
            project = {
                **body,
                "id": project_id,
                "updatedAt": body.get("updatedAt") or iso_now(),
            }
            projects[project_id] = project
            write_projects(projects)
            self.send_json({"project": project}, status=201)
            return
        if parsed.path == "/api/accounts/local-login":
            accounts = read_accounts()
            email = str(body.get("email", "local@auralyze.dev")).strip().lower()
            account = accounts.get(email) or {
                "id": str(uuid4()),
                "email": email,
                "plan": "local-prototype",
            }
            accounts[email] = account
            write_accounts(accounts)
            self.send_json({"account": account, "token": f"local-{account['id']}"})
            return
        if parsed.path == "/api/billing/checkout":
            plan = str(body.get("plan", "pro")).lower()
            email = str(body.get("email", "local@auralyze.dev")).strip().lower()
            if os.environ.get("STRIPE_SECRET_KEY"):
                self.send_json(
                    {
                        "mode": "stripe-placeholder",
                        "plan": plan,
                        "email": email,
                        "message": "External checkout is configured. Attach checkout session creation here if you commercialize later.",
                    },
                    status=201,
                )
                return
            accounts = read_accounts()
            account = accounts.get(email) or {
                "id": str(uuid4()),
                "email": email,
                "plan": "local-prototype",
            }
            account["plan"] = plan
            account["billingMode"] = "local-demo"
            accounts[email] = account
            write_accounts(accounts)
            self.send_json(
                {
                    "mode": "local-demo",
                    "account": account,
                    "message": "Free local plan activated. Paid checkout is optional and disabled by default.",
                },
                status=201,
            )
            return
        if parsed.path == "/api/knowledge/documents":
            if not self.ensure_auth_if_required():
                return
            documents = read_knowledge_documents()
            document_id = body.get("id") or str(uuid4())
            tags = body.get("tags", [])
            if isinstance(tags, str):
                tags = [tag.strip() for tag in tags.split(",") if tag.strip()]
            document = {
                "id": document_id,
                "title": body.get("title", "Untitled reference"),
                "text": body.get("text", ""),
                "tags": tags,
            }
            documents[document_id] = document
            write_knowledge_documents(documents)
            self.send_json(
                {"document": document, "chunkCount": len(chunk_document(document))},
                status=201,
            )
            return
        if parsed.path == "/api/copilot":
            question = str(body.get("question", ""))
            report = body.get("report", {})
            context = json.dumps(report, indent=2) if isinstance(report, dict) else str(body.get("context", ""))
            hits = search_knowledge(f"{question} {context}")
            answer = build_llm_answer(question, report, hits)
            self.send_json(answer)
            return
        if parsed.path == "/api/stem-separation/jobs":
            self.send_json(
                {
                    "job": {
                        "id": str(uuid4()),
                        "status": "queued",
                        "mode": "external-model-required",
                        "expectedStems": body.get(
                            "stems", ["vocals", "drums", "bass", "other"]
                        ),
                    }
                },
                status=202,
            )
            return
        if parsed.path == "/api/plugin-presets":
            self.send_json(
                {
                    "preset": {
                        "id": str(uuid4()),
                        "format": body.get("format", "generic-json"),
                        "chain": body.get("chain", []),
                        "note": "Preset writer scaffold. Attach REAPER, VST, CLAP, or DAW-specific exporters here.",
                    }
                },
                status=201,
            )
            return
        if parsed.path == "/api/format/inspect":
            filename = str(body.get("filename", "audio.wav"))
            suffix = Path(filename).suffix.lower().lstrip(".")
            supported = suffix in {"wav"}
            self.send_json(
                {
                    "filename": filename,
                    "container": suffix or "unknown",
                    "supportedNow": supported,
                    "route": "client-wav-decoder" if supported else "backend-transcode-worker",
                }
            )
            return
        self.send_error(404, "Route not found")

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        project_match = re.fullmatch(r"/api/projects/(?P<project_id>[^/]+)", parsed.path)
        if project_match:
            if not self.ensure_auth_if_required():
                return
            projects = read_projects()
            removed = projects.pop(project_match.group("project_id"), None)
            write_projects(projects)
            self.send_json({"deleted": removed is not None})
            return
        self.send_error(404, "Route not found")

    def ensure_auth_if_required(self) -> bool:
        if not auth_required():
            return True
        try:
            verify_bearer_token(self.headers.get("authorization"))
            return True
        except ValueError as error:
            self.send_json(
                {
                    "error": "Authentication required.",
                    "detail": str(error),
                    "provider": auth_provider(),
                },
                status=401,
            )
            return False

    def handle_stem_separation(self) -> None:
        try:
            filename, upload = self.read_multipart_file("file")
            suffix = Path(filename).suffix or ".audio"
            command = demucs_command()
            if command is None:
                self.handle_ffmpeg_stem_fallback(
                    filename,
                    upload,
                    "Demucs is not installed; used free FFmpeg spectral fallback.",
                )
                return
            if suffix.lower() != ".wav" and ffmpeg_path() is None:
                self.send_json(
                    {
                        "error": "FFmpeg is required to separate non-WAV files.",
                        "installHint": "Upload WAV for now, or install FFmpeg and set FFMPEG_PATH in .env.",
                    },
                    status=503,
                )
                return
            safe_name = re.sub(r"[^a-zA-Z0-9_.-]+", "_", Path(filename).stem) or "mix"
            with tempfile.TemporaryDirectory() as tmp:
                tmp_path = Path(tmp)
                input_path = tmp_path / f"{safe_name}{suffix}"
                output_root = tmp_path / "separated"
                input_path.write_bytes(upload)
                model = os.environ.get("DEMUCS_MODEL", "htdemucs")
                try:
                    result = subprocess.run(
                        [
                            *command,
                            "-n",
                            model,
                            "--out",
                            str(output_root),
                            str(input_path),
                        ],
                        capture_output=True,
                        text=True,
                        timeout=900,
                        check=False,
                    )
                except OSError as error:
                    if ffmpeg_path() is not None:
                        self.handle_ffmpeg_stem_fallback(
                            filename,
                            upload,
                            "Demucs command could not start; used free FFmpeg spectral fallback.",
                            detail=str(error),
                        )
                        return
                    raise
                stem_dir = output_root / model / safe_name
                if result.returncode != 0 or not stem_dir.exists():
                    if ffmpeg_path() is not None:
                        self.handle_ffmpeg_stem_fallback(
                            filename,
                            upload,
                            "Demucs failed; used free FFmpeg spectral fallback.",
                            detail=(result.stderr or result.stdout)[-1200:],
                        )
                        return
                    self.send_json(
                        {
                            "error": "Demucs could not separate this file.",
                            "detail": (result.stderr or result.stdout)[-1600:],
                        },
                        status=422,
                    )
                    return
                stems = []
                for role in ["vocals", "drums", "bass", "other"]:
                    path = stem_dir / f"{role}.wav"
                    if not path.exists():
                        continue
                    data = path.read_bytes()
                    stems.append(
                        {
                            "name": f"{safe_name}_{role}.wav",
                            "role": role,
                            "format": "wav",
                            "bytesBase64": base64.b64encode(data).decode("ascii"),
                        }
                    )
                if not stems:
                    self.send_json(
                        {
                            "error": "Demucs finished but no WAV stems were found.",
                            "detail": (result.stderr or result.stdout)[-1600:],
                        },
                        status=422,
                    )
                    return
                self.send_json(
                    {
                        "source": filename,
                        "engine": "Demucs",
                        "model": model,
                        "stems": stems,
                    }
                )
        except subprocess.TimeoutExpired:
            self.send_json(
                {
                    "error": "Stem separation timed out.",
                    "installHint": "Try a shorter audio file for the prototype, or run Demucs on a machine with a stronger CPU/GPU.",
                },
                status=504,
            )
        except Exception as error:
            self.send_json({"error": f"Stem separation failed: {error}"}, status=400)

    def handle_ffmpeg_stem_fallback(
        self,
        filename: str,
        upload: bytes,
        reason: str,
        detail: str | None = None,
    ) -> None:
        safe_name = re.sub(r"[^a-zA-Z0-9_.-]+", "_", Path(filename).stem) or "mix"
        suffix = Path(filename).suffix or ".audio"
        path = ffmpeg_path()
        if path is None:
            if suffix.lower() == ".wav":
                self.send_wav_diagnostic_stems(
                    filename,
                    upload,
                    reason,
                    "FFmpeg was unavailable; returned duplicate diagnostic WAV stems.",
                )
                return
            self.send_json(
                {
                    "error": "Neither Demucs nor FFmpeg fallback is available.",
                    "installHint": "Install FFmpeg for the free hosted fallback, or install Demucs for true source separation.",
                },
                status=503,
            )
            return
        max_seconds = int(os.environ.get("AURALYZE_FALLBACK_MAX_SECONDS", "180"))
        filters = [
            (
                "vocals",
                "highpass=f=120,lowpass=f=6000,equalizer=f=250:t=q:w=1:g=-3,equalizer=f=3200:t=q:w=1:g=3",
            ),
            (
                "drums",
                "highpass=f=70,lowpass=f=10000,equalizer=f=120:t=q:w=1:g=2,equalizer=f=5000:t=q:w=1:g=4",
            ),
            ("bass", "lowpass=f=180,equalizer=f=75:t=q:w=1:g=5"),
            (
                "other",
                "highpass=f=180,lowpass=f=12000,equalizer=f=3000:t=q:w=1:g=-2",
            ),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            input_path = tmp_path / f"{safe_name}{suffix}"
            input_path.write_bytes(upload)
            stems = []
            errors = []
            for role, audio_filter in filters:
                output_path = tmp_path / f"{safe_name}_{role}.wav"
                command = [
                    path,
                    "-y",
                    "-i",
                    str(input_path),
                    "-vn",
                ]
                if max_seconds > 0:
                    command.extend(["-t", str(max_seconds)])
                command.extend(
                    [
                        "-af",
                        audio_filter,
                        "-ac",
                        "1",
                        "-ar",
                        "44100",
                        "-acodec",
                        "pcm_s16le",
                        str(output_path),
                    ]
                )
                try:
                    result = subprocess.run(
                        command,
                        capture_output=True,
                        text=True,
                        timeout=max(120, min(360, max_seconds + 90)),
                        check=False,
                    )
                except OSError as error:
                    if suffix.lower() == ".wav":
                        self.send_wav_diagnostic_stems(
                            filename,
                            upload,
                            reason,
                            f"FFmpeg could not start: {error}",
                        )
                        return
                    raise
                if result.returncode != 0 or not output_path.exists():
                    errors.append(f"{role}: {(result.stderr or result.stdout)[-600:]}")
                    continue
                stems.append(
                    {
                        "name": f"{safe_name}_{role}.wav",
                        "role": role,
                        "format": "wav",
                        "bytesBase64": base64.b64encode(output_path.read_bytes()).decode(
                            "ascii"
                        ),
                    }
                )
            if not stems:
                self.send_json(
                    {
                        "error": "FFmpeg fallback could not create stems.",
                        "detail": "\n".join(errors)[-1800:],
                    },
                    status=422,
                )
                return
            self.send_json(
                {
                    "source": filename,
                    "engine": "FFmpeg spectral fallback",
                    "model": "band-split-v1",
                    "fallback": True,
                    "approximate": True,
                    "reason": reason,
                    "detail": detail,
                    "maxSeconds": max_seconds,
                    "stems": stems,
                    "note": "These are approximate frequency-shaped stems for free hosted demos, not neural source separation.",
                }
            )

    def send_wav_diagnostic_stems(
        self,
        filename: str,
        upload: bytes,
        reason: str,
        detail: str,
    ) -> None:
        safe_name = re.sub(r"[^a-zA-Z0-9_.-]+", "_", Path(filename).stem) or "mix"
        stems = [
            {
                "name": f"{safe_name}_{role}.wav",
                "role": role,
                "format": "wav",
                "bytesBase64": base64.b64encode(upload).decode("ascii"),
            }
            for role in ["vocals", "drums", "bass", "other"]
        ]
        self.send_json(
            {
                "source": filename,
                "engine": "WAV diagnostic fallback",
                "model": "duplicate-wav-v1",
                "fallback": True,
                "approximate": True,
                "reason": reason,
                "detail": detail,
                "stems": stems,
                "note": "These duplicate WAV stems keep diagnosis working when hosted separation tools are unavailable.",
            }
        )

    def handle_audio_transcode(self) -> None:
        path = ffmpeg_path()
        if path is None:
            self.send_json(
                {
                    "error": "FFmpeg is not installed or FFMPEG_PATH is not set.",
                    "installHint": "Install FFmpeg and make ffmpeg available on PATH, or set FFMPEG_PATH to ffmpeg.exe.",
                },
                status=503,
            )
            return
        try:
            filename, upload = self.read_multipart_file("file")
            suffix = Path(filename).suffix or ".audio"
            if suffix.lower() == ".wav":
                self.send_bytes(
                    upload,
                    "audio/wav",
                    f"{Path(filename).stem}.wav",
                )
                return
            with tempfile.TemporaryDirectory() as tmp:
                input_path = Path(tmp) / f"input{suffix}"
                output_path = Path(tmp) / "output.wav"
                input_path.write_bytes(upload)
                result = subprocess.run(
                    [
                        path,
                        "-y",
                        "-i",
                        str(input_path),
                        "-ac",
                        "1",
                        "-ar",
                        "44100",
                        "-acodec",
                        "pcm_s16le",
                        str(output_path),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=90,
                    check=False,
                )
                if result.returncode != 0 or not output_path.exists():
                    self.send_json(
                        {
                            "error": "FFmpeg could not transcode this file.",
                            "detail": result.stderr[-1200:],
                        },
                        status=422,
                    )
                    return
                self.send_bytes(
                    output_path.read_bytes(),
                    "audio/wav",
                    f"{Path(filename).stem}.wav",
                )
        except Exception as error:
            self.send_json({"error": f"Transcode failed: {error}"}, status=400)

    def read_multipart_file(self, field_name: str) -> tuple[str, bytes]:
        content_type = self.headers.get("content-type", "")
        match = re.search(r"boundary=(?P<boundary>[^;]+)", content_type)
        if not match:
            raise ValueError("Missing multipart boundary.")
        boundary = match.group("boundary").strip('"')
        length = int(self.headers.get("content-length", "0"))
        if length <= 0:
            raise ValueError("Missing upload body.")
        if length > 120 * 1024 * 1024:
            raise ValueError("Upload is too large. Limit is 120 MB.")
        body = self.rfile.read(length)
        delimiter = f"--{boundary}".encode("utf-8")
        for part in body.split(delimiter):
            if b"Content-Disposition" not in part:
                continue
            header_blob, _, content = part.partition(b"\r\n\r\n")
            headers = header_blob.decode("utf-8", errors="replace")
            if f'name="{field_name}"' not in headers:
                continue
            filename_match = re.search(r'filename="(?P<filename>[^"]+)"', headers)
            filename = filename_match.group("filename") if filename_match else "upload.audio"
            return filename, content.rstrip(b"\r\n-")
        raise ValueError(f"Multipart field '{field_name}' was not found.")

    def read_body(self) -> dict:
        length = int(self.headers.get("content-length", "0"))
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return {}

    def send_json(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.add_cors_headers()
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_bytes(self, data: bytes, content_type: str, filename: str) -> None:
        self.send_response(200)
        self.send_header("content-type", content_type)
        self.add_cors_headers()
        self.send_header("content-disposition", f'attachment; filename="{filename}"')
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def add_cors_headers(self) -> None:
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("access-control-allow-headers", "content-type, authorization")

    def log_message(self, format: str, *args: object) -> None:
        return

    def serve_static(self, request_path: str) -> bool:
        web_dir = os.environ.get("AURALYZE_WEB_DIR")
        if not web_dir:
            return False
        root = Path(web_dir).resolve()
        if not root.exists():
            return False
        relative = unquote(request_path).lstrip("/") or "index.html"
        if relative.startswith(".") or "/." in relative.replace("\\", "/"):
            self.send_error(404, "File not found")
            return True
        candidate = (root / relative).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            self.send_error(403, "Forbidden")
            return True
        if candidate.is_dir():
            candidate = candidate / "index.html"
        if not candidate.exists() and "." not in Path(relative).name:
            candidate = root / "index.html"
        if not candidate.exists() or not candidate.is_file():
            self.send_error(404, "File not found")
            return True
        content_type = mimetypes.guess_type(str(candidate))[0] or "application/octet-stream"
        payload = candidate.read_bytes()
        self.send_response(200)
        self.add_cors_headers()
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        return True


def search_knowledge(query: str) -> list[dict]:
    query_tokens = tokenize(query)
    if not query_tokens:
        return []
    scored = []
    for chunk in knowledge_chunks():
        chunk_tokens = set(chunk["tokens"])
        overlap = sum(1 for token in query_tokens if token in chunk_tokens)
        phrase_boost = 2 if any(keyword in query.lower() for keyword in chunk["keywords"]) else 0
        score = overlap + phrase_boost
        if score > 0:
            scored.append((score, chunk))
    results = []
    for score, chunk in sorted(scored, key=lambda pair: pair[0], reverse=True)[:5]:
        results.append(
            {
                "topic": chunk["title"],
                "keywords": chunk["keywords"],
                "guidance": chunk.get("summary", chunk["text"][:420]),
                "move": chunk.get("move", "Use this retrieved reference when advising the user."),
                "source": chunk["source"],
                "sourceType": chunk.get("sourceType", "note"),
                "causes": chunk.get("causes", []),
                "fixes": chunk.get("fixes", []),
                "tools": chunk.get("tools", []),
                "score": score,
            }
        )
    return results


def knowledge_chunks() -> list[dict]:
    chunks = []
    for item in KNOWLEDGE:
        text = f"{item['guidance']} {item['move']}"
        chunks.append(
            {
                "id": f"built-in-{item['topic']}",
                "title": item["topic"],
                "source": "built-in",
                "keywords": item["keywords"],
                "text": text,
                "tokens": tokenize(" ".join(item["keywords"]) + " " + text),
            }
        )
    for document in read_knowledge_documents().values():
        chunks.extend(chunk_document(document))
    for path in sorted(KNOWLEDGE_DIR.glob("*.md")):
        chunks.extend(
            chunk_document(
                {
                    "id": path.stem,
                    "title": path.stem.replace("_", " ").title(),
                    "text": path.read_text(encoding="utf-8"),
                    "tags": path.stem.replace("_", " ").split(),
                    "source": str(path.relative_to(ROOT)),
                }
            )
        )
    for path in sorted(KNOWLEDGE_DIR.glob("*.okf.json")):
        chunks.extend(okf_chunks(path))
    return chunks


def okf_chunks(path: Path) -> list[dict]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        return []
    chunks = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        title = str(entry.get("title", entry.get("id", "Untitled OKF entry")))
        tags = [tag.lower() for tag in string_list(entry.get("tags", []))]
        symptoms = string_list(entry.get("symptoms", []))
        causes = string_list(entry.get("causes", []))
        fixes = string_list(entry.get("fixes", []))
        tools = string_list(entry.get("tools", []))
        text = " ".join(
            [
                f"Symptoms: {'; '.join(symptoms)}.",
                f"Causes: {'; '.join(causes)}.",
                f"Fixes: {'; '.join(fixes)}.",
                f"Tools: {'; '.join(tools)}.",
            ]
        )
        summary_parts = []
        if causes:
            summary_parts.append(f"Likely cause: {causes[0]}.")
        if fixes:
            summary_parts.append(f"Recommended fix: {fixes[0]}.")
        if tools:
            summary_parts.append(f"Tools: {', '.join(tools[:3])}.")
        move = fixes[0] if fixes else "Use the matched OKF entry to guide the user."
        chunks.append(
            {
                "id": f"okf:{path.stem}:{entry.get('id', title)}",
                "title": title,
                "source": str(path.relative_to(ROOT)),
                "sourceType": "okf",
                "keywords": tags + tokenize(title),
                "text": text,
                "summary": " ".join(summary_parts) or text[:420],
                "move": move,
                "causes": causes,
                "fixes": fixes,
                "tools": tools,
                "tokens": tokenize(
                    " ".join([title, *tags, *symptoms, *causes, *fixes, *tools])
                ),
            }
        )
    return chunks


def string_list(value: object) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


def chunk_document(document: dict) -> list[dict]:
    text = str(document.get("text", "")).strip()
    if not text:
        return []
    title = str(document.get("title", "Untitled reference"))
    source = str(document.get("source", f"stored:{document.get('id', title)}"))
    tags = [str(tag).lower() for tag in document.get("tags", [])]
    raw_sections = [section.strip() for section in re.split(r"\n\s*\n+", text) if section.strip()]
    sections = raw_sections or [text]
    chunks = []
    for index, section in enumerate(sections):
        section_tokens = tokenize(section)
        if not section_tokens:
            continue
        chunks.append(
            {
                "id": f"{document.get('id', title)}-{index}",
                "title": title,
                "source": source,
                "keywords": tags,
                "text": section,
                "tokens": tokenize(title + " " + " ".join(tags) + " " + section),
            }
        )
    return chunks


def list_knowledge_documents() -> list[dict]:
    stored = [
        {
            "id": doc_id,
            "title": doc.get("title", "Untitled reference"),
            "tags": doc.get("tags", []),
            "chunkCount": len(chunk_document(doc)),
            "source": "stored",
        }
        for doc_id, doc in read_knowledge_documents().items()
    ]
    files = [
        {
            "id": path.stem,
            "title": path.stem.replace("_", " ").title(),
            "tags": path.stem.replace("_", " ").split(),
            "chunkCount": len(
                chunk_document(
                    {
                        "id": path.stem,
                        "title": path.stem,
                        "text": path.read_text(encoding="utf-8"),
                        "tags": path.stem.replace("_", " ").split(),
                    }
                )
            ),
            "source": str(path.relative_to(ROOT)),
        }
        for path in sorted(KNOWLEDGE_DIR.glob("*.md"))
    ]
    okf_files = [
        {
            "id": path.stem,
            "title": okf_title(path),
            "tags": ["okf", "structured-knowledge"],
            "chunkCount": len(okf_chunks(path)),
            "source": str(path.relative_to(ROOT)),
        }
        for path in sorted(KNOWLEDGE_DIR.glob("*.okf.json"))
    ]
    return [*stored, *files, *okf_files]


def okf_title(path: Path) -> str:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        title = payload.get("title")
        if isinstance(title, str) and title.strip():
            return title
    except (OSError, json.JSONDecodeError):
        pass
    return path.stem.replace("_", " ").title()


def tokenize(value: str) -> list[str]:
    stopwords = {
        "the",
        "and",
        "for",
        "with",
        "that",
        "this",
        "your",
        "from",
        "into",
        "when",
        "then",
        "than",
        "only",
        "around",
    }
    return [
        token
        for token in re.findall(r"[a-z0-9]+", value.lower())
        if len(token) > 2 and token not in stopwords
    ]


def build_local_answer(question: str, hits: list[dict]) -> str:
    if not hits:
        return "Start with level matching, then check tonal balance, dynamics, stereo translation, and timeline markers."
    first = hits[0]
    if first.get("sourceType") == "okf":
        causes = first.get("causes", [])
        fixes = first.get("fixes", [])
        tools = first.get("tools", [])
        cause_text = f" Likely cause: {causes[0]}." if causes else ""
        fix_text = f" Try this first: {fixes[0]}." if fixes else ""
        tool_text = f" Useful free tools: {', '.join(tools[:3])}." if tools else ""
        return f"{first['topic']}.{cause_text}{fix_text}{tool_text}".strip()
    guidance = str(first.get("guidance", "")).strip()
    move = str(first.get("move", "")).strip()
    if not move or "Use this retrieved reference" in move:
        return guidance
    return f"{guidance} Recommended move: {move}"


def ai_status() -> dict:
    provider = os.environ.get("AI_PROVIDER", "ollama").strip().lower()
    if provider == "openai":
        configured = bool(os.environ.get("OPENAI_API_KEY"))
        return {
            "configured": configured,
            "free": False,
            "provider": "openai",
            "mode": "openai-ready" if configured else "openai-missing-key",
            "model": os.environ.get("OPENAI_MODEL", "gpt-4.1-mini"),
            "installHint": "For a free setup, set AI_PROVIDER=ollama and run a local Ollama model.",
        }

    if provider in {"rules", "local-rules"}:
        return {
            "configured": True,
            "free": True,
            "provider": "local-rules",
            "mode": "local-rag-rules",
            "model": "deterministic-dsp-rag",
            "installHint": "No model required. Answers use the audio report plus local OKF/RAG notes.",
        }

    model = os.environ.get("OLLAMA_MODEL", "llama3.2:3b")
    url = ollama_base_url()
    status = ollama_server_status(url, model)
    if status["running"] and status["modelAvailable"]:
        mode = "local-llm-ready"
    elif status["running"]:
        mode = "ollama-model-missing"
    else:
        mode = "local-rag-rules"
    return {
        "configured": status["running"] and status["modelAvailable"],
        "free": True,
        "provider": "ollama" if status["running"] else "local-rules",
        "mode": mode,
        "model": model if status["running"] else "deterministic-dsp-rag",
        "ollamaUrl": url,
        "ollamaRunning": status["running"],
        "ollamaModelAvailable": status["modelAvailable"],
        "availableModels": status["availableModels"],
        "installHint": f"Install Ollama and run: ollama pull {model}",
    }


def auth_provider() -> str:
    provider = os.environ.get("AURALYZE_AUTH_PROVIDER", "local").strip().lower()
    if provider in {"clerk", "firebase"}:
        return provider
    return "local"


def auth_required() -> bool:
    return os.environ.get("AURALYZE_REQUIRE_AUTH", "false").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def auth_status() -> dict:
    provider = auth_provider()
    if provider == "clerk":
        issuer = clerk_issuer()
        return {
            "provider": "clerk",
            "configured": bool(issuer or os.environ.get("CLERK_JWKS_URL")),
            "free": True,
            "requireAuth": auth_required(),
            "mode": "clerk-ready"
            if issuer or os.environ.get("CLERK_JWKS_URL")
            else "clerk-missing-config",
            "installHint": "Set CLERK_ISSUER or CLERK_JWKS_URL after creating a free Clerk app.",
        }
    if provider == "firebase":
        project_id = os.environ.get("FIREBASE_PROJECT_ID")
        return {
            "provider": "firebase",
            "configured": bool(project_id),
            "free": True,
            "requireAuth": auth_required(),
            "mode": "firebase-ready" if project_id else "firebase-missing-project",
            "installHint": "Set FIREBASE_PROJECT_ID after creating a Firebase Spark project.",
        }
    return {
        "provider": "local",
        "configured": True,
        "free": True,
        "requireAuth": auth_required(),
        "mode": "local-demo-auth",
        "installHint": "Use Clerk or Firebase env vars when you want hosted identity.",
    }


def verify_bearer_token(header: str | None) -> dict:
    provider = auth_provider()
    if provider == "local":
        return {"id": "local-demo", "provider": "local", "email": "local@auralyze.dev"}
    token = bearer_token(header)
    if provider == "clerk":
        return verify_clerk_token(token)
    if provider == "firebase":
        return verify_firebase_token(token)
    raise ValueError(f"Unsupported auth provider: {provider}")


def bearer_token(header: str | None) -> str:
    if not header:
        raise ValueError("Missing Authorization: Bearer token.")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise ValueError("Expected Authorization: Bearer <token>.")
    return token.strip()


def verify_clerk_token(token: str) -> dict:
    issuer = clerk_issuer()
    jwks_url = os.environ.get("CLERK_JWKS_URL") or (
        f"{issuer.rstrip('/')}/.well-known/jwks.json" if issuer else ""
    )
    if not jwks_url:
        raise ValueError("CLERK_ISSUER or CLERK_JWKS_URL is not configured.")
    payload = verify_jwt(
        token,
        jwks_url=jwks_url,
        issuer=issuer,
        audience=os.environ.get("CLERK_AUDIENCE"),
    )
    return {
        "id": payload.get("sub", ""),
        "provider": "clerk",
        "email": payload.get("email") or payload.get("primary_email_address_id"),
        "claims": safe_claims(payload),
    }


def verify_firebase_token(token: str) -> dict:
    project_id = os.environ.get("FIREBASE_PROJECT_ID")
    if not project_id:
        raise ValueError("FIREBASE_PROJECT_ID is not configured.")
    payload = verify_jwt(
        token,
        jwks_url="https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
        issuer=f"https://securetoken.google.com/{project_id}",
        audience=project_id,
    )
    firebase_claims = payload.get("firebase", {})
    return {
        "id": payload.get("sub", ""),
        "provider": "firebase",
        "email": payload.get("email"),
        "signInProvider": firebase_claims.get("sign_in_provider")
        if isinstance(firebase_claims, dict)
        else None,
        "claims": safe_claims(payload),
    }


def verify_jwt(
    token: str,
    *,
    jwks_url: str,
    issuer: str | None = None,
    audience: str | None = None,
) -> dict:
    try:
        import jwt
        from jwt import PyJWKClient
    except ImportError as error:
        raise ValueError(
            "JWT verification dependencies are missing. Install requirements.txt."
        ) from error
    signing_key = PyJWKClient(jwks_url).get_signing_key_from_jwt(token).key
    options = {
        "verify_aud": bool(audience),
        "verify_iss": bool(issuer),
    }
    try:
        payload = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            audience=audience,
            issuer=issuer,
            options=options,
        )
    except jwt.PyJWTError as error:
        raise ValueError(f"Invalid token: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError("Invalid token payload.")
    return payload


def clerk_issuer() -> str:
    return (
        os.environ.get("CLERK_ISSUER")
        or os.environ.get("CLERK_JWT_ISSUER")
        or ""
    ).strip()


def safe_claims(payload: dict) -> dict:
    keep = ["sub", "email", "name", "iss", "aud", "exp", "iat"]
    return {key: payload[key] for key in keep if key in payload}


def ollama_base_url() -> str:
    return os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")


def ollama_server_status(url: str, model: str) -> dict:
    request = urllib.request.Request(f"{url}/api/tags", method="GET")
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            data = json.loads(response.read().decode("utf-8"))
    except Exception:
        return {"running": False, "modelAvailable": False, "availableModels": []}
    names = [
        item.get("name", "")
        for item in data.get("models", [])
        if isinstance(item, dict)
    ]
    base_names = [name.split(":", 1)[0] for name in names]
    model_available = model in names or model.split(":", 1)[0] in base_names
    return {
        "running": True,
        "modelAvailable": model_available,
        "availableModels": names,
    }


def build_llm_answer(question: str, report: object, hits: list[dict]) -> dict:
    provider = os.environ.get("AI_PROVIDER", "ollama").strip().lower()
    if provider not in {"openai", "rules", "local-rules"}:
        ollama_answer = build_ollama_answer(question, report, hits)
        if ollama_answer.get("answer"):
            return ollama_answer
        return {
            "answer": build_local_answer(question, hits),
            "sources": hits,
            "mode": "local-rules",
            "model": "deterministic-dsp-rag",
            "error": ollama_answer.get("error"),
        }

    if provider in {"rules", "local-rules"}:
        return {
            "answer": build_local_answer(question, hits),
            "sources": hits,
            "mode": "local-rules",
            "model": "deterministic-dsp-rag",
        }

    return build_openai_answer(question, report, hits)


def ai_prompt(question: str, report: object, hits: list[dict]) -> str:
    return (
        "You are Auralyze, an audio production copilot. "
        "Give practical, specific advice based only on the audio report and retrieved notes. "
        "Prioritize free/open-source tools and fixes the user can do now. "
        "Keep the answer under 180 words.\n\n"
        f"User question:\n{question}\n\n"
        f"Audio analysis report:\n{json.dumps(compact_report(report), indent=2)}\n\n"
        f"Retrieved production notes:\n{json.dumps(hits, indent=2)}"
    )


def build_ollama_answer(question: str, report: object, hits: list[dict]) -> dict:
    model = os.environ.get("OLLAMA_MODEL", "llama3.2:3b")
    status = ollama_server_status(ollama_base_url(), model)
    if not status["running"]:
        return {
            "answer": "",
            "sources": hits,
            "mode": "local-rules",
            "model": model,
            "error": "Ollama is not running. Install/start Ollama or continue with local DSP/OKF rules.",
        }
    if not status["modelAvailable"]:
        return {
            "answer": "",
            "sources": hits,
            "mode": "local-rules",
            "model": model,
            "error": f"Ollama is running but {model} is not pulled yet. Run: ollama pull {model}",
        }
    payload = {
        "model": model,
        "prompt": ai_prompt(question, report, hits),
        "stream": False,
        "options": {"temperature": 0.2, "num_predict": 420},
    }
    request = urllib.request.Request(
        f"{ollama_base_url()}/api/generate",
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            data = json.loads(response.read().decode("utf-8"))
        return {
            "answer": str(data.get("response", "")).strip(),
            "sources": hits,
            "mode": "ollama",
            "model": model,
        }
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        return {
            "answer": "",
            "sources": hits,
            "mode": "local-rules",
            "model": model,
            "error": f"Ollama request failed with HTTP {error.code}: {detail[:400]}",
        }
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        return {
            "answer": "",
            "sources": hits,
            "mode": "local-rules",
            "model": model,
            "error": f"Ollama request failed: {error}",
        }


def build_openai_answer(question: str, report: object, hits: list[dict]) -> dict:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        return {
            "answer": build_local_answer(question, hits),
            "sources": hits,
            "mode": "local-rules",
            "model": "deterministic-dsp-rag",
            "error": "AI_PROVIDER=openai but OPENAI_API_KEY is not set.",
        }

    model = os.environ.get("OPENAI_MODEL", "gpt-4.1-mini")
    prompt = {
        "role": "user",
        "content": [
            {"type": "input_text", "text": ai_prompt(question, report, hits)}
        ],
    }
    payload = {
        "model": model,
        "input": [prompt],
        "max_output_tokens": 420,
    }
    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "authorization": f"Bearer {api_key}",
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=35) as response:
            data = json.loads(response.read().decode("utf-8"))
        return {
            "answer": extract_response_text(data),
            "sources": hits,
            "mode": "openai",
            "model": model,
        }
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        return {
            "answer": build_local_answer(question, hits),
            "sources": hits,
            "mode": "local-rules",
            "model": model,
            "error": f"OpenAI request failed with HTTP {error.code}: {detail[:400]}",
        }
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        return {
            "answer": build_local_answer(question, hits),
            "sources": hits,
            "mode": "local-rules",
            "model": model,
            "error": f"OpenAI request failed: {error}",
        }


def compact_report(report: object) -> dict:
    if not isinstance(report, dict):
        return {"context": str(report)[:2000]}
    return {
        "fileName": report.get("fileName"),
        "releaseTarget": report.get("releaseTarget"),
        "metrics": report.get("metrics", {}),
        "issues": report.get("issues", [])[:6],
        "timeline": report.get("timeline", [])[:6],
        "conflicts": report.get("conflicts", [])[:6],
        "stems": report.get("stems", [])[:8],
        "referenceMatch": report.get("referenceMatch", {}),
        "fixes": report.get("fixes", [])[:8],
        "plugins": report.get("plugins", [])[:8],
    }


def extract_response_text(data: dict) -> str:
    if isinstance(data.get("output_text"), str):
        return data["output_text"]
    chunks = []
    for item in data.get("output", []):
        for content in item.get("content", []):
            text = content.get("text")
            if isinstance(text, str):
                chunks.append(text)
    return "\n".join(chunks).strip() or "I could not extract a response from the model."


def read_projects() -> dict:
    return read_store("projects", PROJECTS_FILE)


def write_projects(projects: dict) -> None:
    write_store("projects", PROJECTS_FILE, projects)


def read_accounts() -> dict:
    return read_store("accounts", ACCOUNTS_FILE)


def write_accounts(accounts: dict) -> None:
    write_store("accounts", ACCOUNTS_FILE, accounts)


def read_knowledge_documents() -> dict:
    return read_store("knowledge", KNOWLEDGE_FILE)


def write_knowledge_documents(documents: dict) -> None:
    write_store("knowledge", KNOWLEDGE_FILE, documents)


def storage_backend() -> str:
    requested = os.environ.get("AURALYZE_STORAGE", "json").strip().lower()
    if requested in {"postgres", "postgresql", "neon"} and os.environ.get(
        "DATABASE_URL"
    ):
        return "postgres"
    return "sqlite" if requested == "sqlite" else "json"


def read_store(name: str, json_path: Path) -> dict:
    backend = storage_backend()
    if backend == "postgres":
        return read_postgres_store(name)
    if backend == "sqlite":
        return read_sqlite_store(name)
    return read_json_file(json_path)


def write_store(name: str, json_path: Path, payload: dict) -> None:
    backend = storage_backend()
    if backend == "postgres":
        write_postgres_store(name, payload)
        return
    if backend == "sqlite":
        write_sqlite_store(name, payload)
        return
    write_json_file(json_path, payload)


def sqlite_connection() -> sqlite3.Connection:
    DATA_DIR.mkdir(exist_ok=True)
    connection = sqlite3.connect(SQLITE_FILE)
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS app_state (
            name TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    return connection


def read_sqlite_store(name: str) -> dict:
    with sqlite_connection() as connection:
        row = connection.execute(
            "SELECT payload FROM app_state WHERE name = ?",
            (name,),
        ).fetchone()
    if row is None:
        return {}
    try:
        payload = json.loads(row[0])
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def write_sqlite_store(name: str, payload: dict) -> None:
    serialized = json.dumps(payload, indent=2)
    with sqlite_connection() as connection:
        connection.execute(
            """
            INSERT INTO app_state (name, payload, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                payload = excluded.payload,
                updated_at = excluded.updated_at
            """,
            (name, serialized, iso_now()),
        )


def postgres_connection():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required for Postgres storage.")
    try:
        import psycopg
    except ImportError as error:
        raise RuntimeError(
            "Postgres storage requires psycopg. Install requirements.txt."
        ) from error
    connection = psycopg.connect(database_url)
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS app_state (
            name TEXT PRIMARY KEY,
            payload JSONB NOT NULL,
            updated_at TIMESTAMPTZ NOT NULL
        )
        """
    )
    connection.commit()
    return connection


def read_postgres_store(name: str) -> dict:
    with postgres_connection() as connection:
        row = connection.execute(
            "SELECT payload FROM app_state WHERE name = %s",
            (name,),
        ).fetchone()
    if row is None:
        return {}
    payload = row[0]
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except json.JSONDecodeError:
            return {}
    return payload if isinstance(payload, dict) else {}


def write_postgres_store(name: str, payload: dict) -> None:
    serialized = json.dumps(payload)
    with postgres_connection() as connection:
        connection.execute(
            """
            INSERT INTO app_state (name, payload, updated_at)
            VALUES (%s, %s::jsonb, %s)
            ON CONFLICT(name) DO UPDATE SET
                payload = EXCLUDED.payload,
                updated_at = EXCLUDED.updated_at
            """,
            (name, serialized, iso_now()),
        )
        connection.commit()


def storage_status() -> dict:
    backend = storage_backend()
    if backend == "postgres":
        path = redact_database_url(os.environ.get("DATABASE_URL", ""))
    elif backend == "sqlite":
        path = SQLITE_FILE
    else:
        path = DATA_DIR
    return {
        "backend": backend,
        "requestedBackend": os.environ.get("AURALYZE_STORAGE", "json"),
        "free": True,
        "path": str(path),
        "projectCount": len(read_projects()),
        "accountCount": len(read_accounts()),
        "knowledgeDocumentCount": len(read_knowledge_documents()),
        "backupEndpoint": "/api/storage/export",
    }


def redact_database_url(value: str) -> str:
    if not value:
        return ""
    parsed = urlparse(value)
    if not parsed.scheme or not parsed.netloc:
        return "configured"
    host = parsed.hostname or ""
    port = f":{parsed.port}" if parsed.port else ""
    user = parsed.username or "user"
    path = parsed.path or ""
    return f"{parsed.scheme}://{user}:***@{host}{port}{path}"


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def billing_plans() -> list[dict]:
    return [
        {
            "id": "free",
            "name": "Local Free",
            "price": 0,
            "features": ["local analysis", "WAV export", "local projects"],
        },
        {
            "id": "pro",
            "name": "Auralyze Local Pro",
            "price": 0,
            "features": [
                "open-source AI copilot",
                "source separation",
                "reference matching",
                "preset exports",
            ],
        },
        {
            "id": "studio",
            "name": "Studio Local",
            "price": 0,
            "features": [
                "team projects",
                "batch analysis",
                "deployment support",
                "priority processing",
            ],
        },
    ]


def read_json_file(path: Path) -> dict:
    DATA_DIR.mkdir(exist_ok=True)
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def write_json_file(path: Path, payload: dict) -> None:
    DATA_DIR.mkdir(exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def product_features() -> list[dict]:
    return [
        {"name": "Open-source copilot", "status": "ollama-or-local-rules-ready"},
        {"name": "OKF/RAG knowledge", "status": "structured-local-index-ready"},
        {"name": "Hosted auth", "status": auth_status()["mode"]},
        {"name": "Persistent storage", "status": f"{storage_backend()}-ready"},
        {"name": "Cloud projects", "status": "local-api-ready"},
        {"name": "Stem separation", "status": "demucs-or-ffmpeg-fallback-ready"},
        {"name": "Format transcode", "status": "ffmpeg-endpoint-ready"},
        {"name": "A/B preview", "status": "client-render-ready"},
        {"name": "Plugin presets", "status": "export-scaffold-ready"},
        {"name": "Deployment", "status": "service-boundary-ready"},
    ]


def mastering_targets() -> list[dict]:
    return [
        {"name": "Spotify", "lufs": -14, "truePeak": -1.0},
        {"name": "YouTube", "lufs": -14, "truePeak": -1.0},
        {"name": "Club", "lufs": -9, "truePeak": -0.3},
        {"name": "Podcast", "lufs": -16, "truePeak": -1.5},
        {"name": "Cinema", "lufs": -23, "truePeak": -2.0},
    ]


def main() -> None:
    load_dotenv()
    host = os.environ.get("AURALYZE_HOST", "127.0.0.1")
    port = int(os.environ.get("PORT") or os.environ.get("AURALYZE_PORT", "8788"))
    server = ThreadingHTTPServer((host, port), AuralyzeHandler)
    print(f"Auralyze backend running on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
