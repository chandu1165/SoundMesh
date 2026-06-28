from __future__ import annotations

import importlib.util
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
    status = server.auth_status()
    local_user = server.verify_bearer_token(None)
    print(f"Auth provider: {status['provider']}")
    print(f"Auth mode: {status['mode']}")
    print(f"Require auth: {status['requireAuth']}")
    print(f"Configured: {status['configured']}")
    print(f"Local user: {local_user['id']}")


if __name__ == "__main__":
    main()
