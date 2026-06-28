from __future__ import annotations

import importlib.util
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "backend" / "server.py"


def load_server_module():
    spec = importlib.util.spec_from_file_location("auralyze_server", SERVER)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load backend/server.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    server = load_server_module()
    server.load_dotenv()
    status = server.storage_status()
    print(f"AURALYZE_STORAGE={os.environ.get('AURALYZE_STORAGE', 'json')}")
    print(f"Storage backend: {status['backend']}")
    print(f"Free local storage: {status['free']}")
    print(f"Path: {status['path']}")
    print(f"Projects: {status['projectCount']}")
    print(f"Accounts: {status['accountCount']}")
    print(f"Custom knowledge docs: {status['knowledgeDocumentCount']}")
    print(f"Backup endpoint: {status['backupEndpoint']}")


if __name__ == "__main__":
    main()
