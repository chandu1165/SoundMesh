from __future__ import annotations

import json
import os
from pathlib import Path
import urllib.request


def read_env() -> dict[str, str]:
    env_file = Path(".env")
    values: dict[str, str] = {}
    if not env_file.exists():
        return values
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def main() -> None:
    values = read_env()
    provider = values.get("AI_PROVIDER", os.environ.get("AI_PROVIDER", "ollama"))
    url = values.get("OLLAMA_URL", os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")).rstrip("/")
    model = values.get("OLLAMA_MODEL", os.environ.get("OLLAMA_MODEL", "llama3.2:3b"))

    print(f"AI_PROVIDER={provider}")
    print(f"OLLAMA_URL={url}")
    print(f"OLLAMA_MODEL={model}")

    try:
        request = urllib.request.Request(f"{url}/api/tags", method="GET")
        with urllib.request.urlopen(request, timeout=2) as response:
            data = json.loads(response.read().decode("utf-8"))
        names = [
            item.get("name", "")
            for item in data.get("models", [])
            if isinstance(item, dict)
        ]
        base_names = [name.split(":", 1)[0] for name in names]
        ready = model in names or model.split(":", 1)[0] in base_names
        print("Ollama server: running")
        print("Models: " + (", ".join(names) if names else "(none pulled yet)"))
        print(f"Selected model ready: {ready}")
    except Exception as exc:
        print("Ollama server: not reachable")
        print(f"Reason: {exc}")
        print("Auralyze will use local DSP/OKF rules until Ollama is running.")


if __name__ == "__main__":
    main()
