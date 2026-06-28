from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "backend" / "okf_mcp_server.py"


class McpSmokeClient:
    def __init__(self) -> None:
        self.next_id = 1
        self.process = subprocess.Popen(
            [sys.executable, str(SERVER)],
            cwd=str(ROOT),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
        )

    def close(self) -> None:
        self.process.terminate()
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill()

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        request_id = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {}})
        assert self.process.stdout is not None
        line = self.process.stdout.readline()
        if not line:
            stderr = self.process.stderr.read() if self.process.stderr else ""
            raise RuntimeError(f"No MCP response for {method}. stderr={stderr}")
        response = json.loads(line)
        if "error" in response:
            raise RuntimeError(f"MCP error for {method}: {response['error']}")
        return response["result"]

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        self.send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def send(self, payload: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()


def main() -> None:
    client = McpSmokeClient()
    try:
        initialized = client.request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "auralyze-okf-smoke", "version": "0.1.0"},
            },
        )
        client.notify("notifications/initialized")
        tools = client.request("tools/list")["tools"]
        search = client.request(
            "tools/call",
            {
                "name": "okf.search",
                "arguments": {"query": "muddy vocal low mids", "limit": 3},
            },
        )
        answer = client.request(
            "tools/call",
            {
                "name": "okf.answer",
                "arguments": {"question": "what should I do for muddy vocals?"},
            },
        )
        resources = client.request("resources/list")["resources"]
        index = client.request(
            "resources/read", {"uri": "okf://knowledge/index"}
        )
        okf_file_uri = next(
            resource["uri"]
            for resource in resources
            if resource["uri"].startswith("okf://file/")
        )
        okf_entry_uri = next(
            resource["uri"]
            for resource in resources
            if resource["uri"].startswith("okf://entry/")
        )
        okf_file = client.request("resources/read", {"uri": okf_file_uri})
        okf_entry = client.request("resources/read", {"uri": okf_entry_uri})
        print(f"Protocol: {initialized['protocolVersion']}")
        print("Tools: " + ", ".join(tool["name"] for tool in tools))
        print("Resources: " + str(len(resources)))
        print(
            "Top search result: "
            + search["structuredContent"]["results"][0]["topic"]
        )
        print("Answer: " + answer["structuredContent"]["answer"])
        index_payload = json.loads(index["contents"][0]["text"])
        print(f"OKF chunks: {index_payload['okfChunkCount']}")
        print("OKF file bytes: " + str(len(okf_file["contents"][0]["text"])))
        print("OKF entry title: " + json.loads(okf_entry["contents"][0]["text"])["title"])
    finally:
        client.close()


if __name__ == "__main__":
    main()
