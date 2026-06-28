from __future__ import annotations

import base64
import importlib.util
import json
import math
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
import tempfile
import threading
import urllib.error
import urllib.request
import uuid
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "backend" / "server.py"


def main() -> None:
    port = free_port()
    env = os.environ.copy()
    env.update(
        {
            "AURALYZE_HOST": "127.0.0.1",
            "AURALYZE_PORT": str(port),
            "AI_PROVIDER": "local-rules",
            "AURALYZE_STORAGE": "sqlite",
            "AURALYZE_FALLBACK_MAX_SECONDS": "1",
            "DEMUCS_COMMAND": "missing-demucs-for-upload-smoke",
        }
    )
    os.environ.update(env)
    server_module = load_server_module()
    server_module.load_dotenv()
    server = server_module.ThreadingHTTPServer(
        ("127.0.0.1", port),
        server_module.AuralyzeHandler,
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base_url = f"http://127.0.0.1:{port}"
        wait_for_health(base_url)
        wav = make_wav_bytes()

        audio_status = get_json(f"{base_url}/api/audio/status")
        stem_status = get_json(f"{base_url}/api/stem-separation/status")
        print(f"Audio status ffmpeg={audio_status.get('ffmpegAvailable')}")
        print(f"Stem mode={stem_status.get('mode')} available={stem_status.get('available')}")

        if audio_status.get("ffmpegAvailable"):
            transcode = multipart_post(
                f"{base_url}/api/audio/transcode",
                "file",
                "upload.wav",
                wav,
            )
            if not transcode.startswith(b"RIFF"):
                raise AssertionError("Transcode route did not return a WAV file.")

            separation = multipart_json(
                f"{base_url}/api/stem-separation/separate",
                "file",
                "upload.wav",
                wav,
            )
            stems = separation.get("stems", [])
            if len(stems) != 4:
                raise AssertionError(f"Expected 4 fallback stems, got {len(stems)}")
            for stem in stems:
                if not stem.get("bytesBase64"):
                    raise AssertionError("Stem missing bytesBase64.")
                decoded = base64.b64decode(stem["bytesBase64"])
                if not decoded.startswith(b"RIFF"):
                    raise AssertionError("Stem is not a WAV file.")
            print(
                f"Stem fallback engine={separation.get('engine')} stems={len(stems)}"
            )
        else:
            print("FFmpeg not available; upload route fallback test skipped.")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def load_server_module():
    spec = importlib.util.spec_from_file_location("auralyze_server", SERVER)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load backend/server.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_for_health(base_url: str) -> None:
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            payload = get_json(f"{base_url}/health")
            if payload.get("ok") is True:
                return
        except Exception:
            time.sleep(0.25)
    raise TimeoutError("Backend did not become healthy.")


def get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def multipart_json(url: str, field: str, filename: str, data: bytes) -> dict:
    return json.loads(multipart_post(url, field, filename, data).decode("utf-8"))


def multipart_post(url: str, field: str, filename: str, data: bytes) -> bytes:
    curl = shutil.which("curl") or shutil.which("curl.exe")
    if curl:
        return curl_multipart_post(curl, url, field, filename, data)
    body, content_type = multipart_body(field, filename, data)
    request = urllib.request.Request(
        url,
        data=body,
        headers={"content-type": content_type},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise AssertionError(f"POST {url} failed: {error.code} {detail}") from error


def curl_multipart_post(
    curl: str,
    url: str,
    field: str,
    filename: str,
    data: bytes,
) -> bytes:
    suffix = Path(filename).suffix or ".audio"
    upload_path = ""
    output_path = ""
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as upload:
            upload.write(data)
            upload_path = upload.name
        with tempfile.NamedTemporaryFile(delete=False) as output:
            output_path = output.name
        result = subprocess.run(
            [
                curl,
                "-sS",
                "-L",
                "--max-time",
                "90",
                "-o",
                output_path,
                "-w",
                "%{http_code}",
                "-X",
                "POST",
                "-F",
                f"{field}=@{upload_path};filename={filename}",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=100,
            check=False,
        )
        response = Path(output_path).read_bytes()
        status = int((result.stdout or "0").strip()[-3:] or "0")
        if status < 200 or status >= 300:
            detail = response.decode("utf-8", errors="replace")
            raise AssertionError(f"POST {url} failed: {status} {detail}")
        return response
    finally:
        for path in [upload_path, output_path]:
            if path:
                Path(path).unlink(missing_ok=True)


def multipart_body(field: str, filename: str, data: bytes) -> tuple[bytes, str]:
    boundary = f"----auralyze-{uuid.uuid4().hex}"
    parts = [
        f"--{boundary}\r\n".encode("utf-8"),
        (
            f'Content-Disposition: form-data; name="{field}"; '
            f'filename="{filename}"\r\n'
        ).encode("utf-8"),
        b"Content-Type: audio/wav\r\n\r\n",
        data,
        b"\r\n",
        f"--{boundary}--\r\n".encode("utf-8"),
    ]
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def make_wav_bytes() -> bytes:
    path = ROOT / "backend" / "data" / "upload-smoke.wav"
    path.parent.mkdir(exist_ok=True)
    sample_rate = 22050
    sample_count = sample_rate // 4
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        frames = b"".join(
            struct.pack(
                "<h",
                int(10000 * math.sin(2 * math.pi * 220 * index / sample_rate)),
            )
            for index in range(sample_count)
        )
        output.writeframes(frames)
    try:
        return path.read_bytes()
    finally:
        path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
