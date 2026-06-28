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
    chunks = server.knowledge_chunks()
    okf_chunks = [chunk for chunk in chunks if chunk.get("sourceType") == "okf"]
    docs = server.list_knowledge_documents()
    print(f"Knowledge chunks: {len(chunks)}")
    print(f"OKF chunks: {len(okf_chunks)}")
    print(f"Documents: {len(docs)}")
    for chunk in okf_chunks[:8]:
        print(f"- {chunk['title']} [{chunk['source']}]")
    results = server.search_knowledge("muddy vocal low mids free fix")
    print("Top query result: " + (results[0]["topic"] if results else "(none)"))


if __name__ == "__main__":
    main()
