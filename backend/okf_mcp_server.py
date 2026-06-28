from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote

import server as auralyze


PROTOCOL_VERSION = "2025-06-18"
SERVER_NAME = "auralyze-okf-mcp"
SERVER_VERSION = "0.1.0"


def main() -> None:
    auralyze.load_dotenv()
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            response = handle_message(request)
        except Exception as error:
            response = error_response(None, -32603, f"Internal error: {error}")
        if response is not None:
            write_message(response)


def handle_message(request: dict[str, Any]) -> dict[str, Any] | None:
    request_id = request.get("id")
    method = request.get("method")
    params = request.get("params") or {}
    if method == "notifications/initialized":
        return None
    if method == "initialize":
        return result_response(request_id, initialize_result(params))
    if method == "ping":
        return result_response(request_id, {})
    if method == "tools/list":
        return result_response(request_id, {"tools": tools()})
    if method == "tools/call":
        return result_response(request_id, call_tool(params))
    if method == "resources/list":
        return result_response(request_id, {"resources": resources()})
    if method == "resources/read":
        return result_response(request_id, read_resource(str(params.get("uri", ""))))
    if method == "resources/templates/list":
        return result_response(
            request_id,
            {
                "resourceTemplates": [
                    {
                        "uriTemplate": "okf://search/{query}",
                        "name": "okf-search",
                        "title": "OKF Search",
                        "description": "Search local Auralyze OKF/RAG knowledge by query.",
                        "mimeType": "application/json",
                    }
                ]
            },
        )
    return error_response(request_id, -32601, f"Method not found: {method}")


def initialize_result(params: dict[str, Any]) -> dict[str, Any]:
    requested = params.get("protocolVersion")
    protocol = requested if isinstance(requested, str) else PROTOCOL_VERSION
    return {
        "protocolVersion": protocol,
        "capabilities": {
            "resources": {"listChanged": False},
            "tools": {"listChanged": False},
        },
        "serverInfo": {
            "name": SERVER_NAME,
            "title": "Auralyze OKF MCP Server",
            "version": SERVER_VERSION,
        },
        "instructions": (
            "Use this server to search Auralyze Open Knowledge Files and "
            "retrieve structured audio diagnosis causes, fixes, tools, and sources."
        ),
    }


def tools() -> list[dict[str, Any]]:
    return [
        {
            "name": "okf.search",
            "title": "Search OKF Knowledge",
            "description": "Search local Auralyze OKF/RAG audio-production knowledge.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Audio problem, symptom, tool, or workflow to search for.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of results to return.",
                        "minimum": 1,
                        "maximum": 5,
                        "default": 5,
                    },
                },
                "required": ["query"],
            },
            "outputSchema": {
                "type": "object",
                "properties": {"results": {"type": "array"}},
                "required": ["results"],
            },
        },
        {
            "name": "okf.answer",
            "title": "Answer With OKF",
            "description": "Generate a concise deterministic answer from local OKF/RAG knowledge.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "question": {"type": "string"},
                    "context": {
                        "type": "string",
                        "description": "Optional extra text from the current audio report.",
                    },
                    "report": {
                        "type": "object",
                        "description": "Optional structured audio report context.",
                    },
                },
                "required": ["question"],
            },
            "outputSchema": {
                "type": "object",
                "properties": {
                    "answer": {"type": "string"},
                    "sources": {"type": "array"},
                },
                "required": ["answer", "sources"],
            },
        },
        {
            "name": "okf.documents",
            "title": "List OKF Documents",
            "description": "List local OKF, markdown, and stored knowledge documents.",
            "inputSchema": {"type": "object", "properties": {}},
            "outputSchema": {
                "type": "object",
                "properties": {"documents": {"type": "array"}},
                "required": ["documents"],
            },
        },
    ]


def call_tool(params: dict[str, Any]) -> dict[str, Any]:
    name = str(params.get("name", ""))
    arguments = params.get("arguments") or {}
    if name == "okf.search":
        query = str(arguments.get("query", "")).strip()
        limit = clamp_int(arguments.get("limit", 5), 1, 5)
        payload = {"results": auralyze.search_knowledge(query)[:limit]}
        return tool_result(payload)
    if name == "okf.answer":
        question = str(arguments.get("question", "")).strip()
        context = str(arguments.get("context", "")).strip()
        report = arguments.get("report", {})
        query_context = f"{question} {context} {json.dumps(report) if isinstance(report, dict) else ''}"
        sources = auralyze.search_knowledge(query_context)
        okf_sources = [source for source in sources if source.get("sourceType") == "okf"]
        answer_sources = okf_sources or sources
        payload = {
            "answer": auralyze.build_local_answer(question, answer_sources),
            "sources": answer_sources,
        }
        return tool_result(payload)
    if name == "okf.documents":
        payload = {"documents": auralyze.list_knowledge_documents()}
        return tool_result(payload)
    raise ValueError(f"Unknown tool: {name}")


def tool_result(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "content": [{"type": "text", "text": json.dumps(payload, indent=2)}],
        "structuredContent": payload,
        "isError": False,
    }


def resources() -> list[dict[str, Any]]:
    items = [
        {
            "uri": "okf://knowledge/index",
            "name": "OKF Knowledge Index",
            "title": "Auralyze OKF Knowledge Index",
            "description": "Summary of local OKF/RAG documents and chunks.",
            "mimeType": "application/json",
        },
        {
            "uri": "okf://knowledge/documents",
            "name": "OKF Documents",
            "title": "Auralyze OKF/RAG Documents",
            "description": "List of local OKF, markdown, and stored knowledge documents.",
            "mimeType": "application/json",
        },
    ]
    for path in sorted(auralyze.KNOWLEDGE_DIR.glob("*.okf.json")):
        rel = str(path.relative_to(auralyze.ROOT)).replace("\\", "/")
        items.append(
            {
                "uri": f"okf://file/{quote(rel, safe='')}",
                "name": path.name,
                "title": auralyze.okf_title(path),
                "description": "Structured Auralyze Open Knowledge File.",
                "mimeType": "application/json",
            }
        )
    for chunk in auralyze.knowledge_chunks():
        if chunk.get("sourceType") != "okf":
            continue
        items.append(
            {
                "uri": f"okf://entry/{quote(str(chunk['id']), safe='')}",
                "name": str(chunk["title"]),
                "title": str(chunk["title"]),
                "description": str(chunk.get("summary", chunk.get("text", "")))[:220],
                "mimeType": "application/json",
            }
        )
    return items


def read_resource(uri: str) -> dict[str, Any]:
    if uri == "okf://knowledge/index":
        payload = {
            "documents": auralyze.list_knowledge_documents(),
            "chunkCount": len(auralyze.knowledge_chunks()),
            "okfChunkCount": len(
                [
                    chunk
                    for chunk in auralyze.knowledge_chunks()
                    if chunk.get("sourceType") == "okf"
                ]
            ),
        }
        return resource_text(uri, payload)
    if uri == "okf://knowledge/documents":
        return resource_text(uri, {"documents": auralyze.list_knowledge_documents()})
    if uri.startswith("okf://file/"):
        return read_okf_file(uri)
    if uri.startswith("okf://entry/"):
        return read_okf_entry(uri)
    if uri.startswith("okf://search/"):
        query = unquote(uri.removeprefix("okf://search/"))
        return resource_text(uri, {"results": auralyze.search_knowledge(query)})
    raise ValueError(f"Unknown resource URI: {uri}")


def read_okf_file(uri: str) -> dict[str, Any]:
    rel = unquote(uri.removeprefix("okf://file/"))
    path = (auralyze.ROOT / rel).resolve()
    knowledge_root = auralyze.KNOWLEDGE_DIR.resolve()
    try:
        path.relative_to(knowledge_root)
    except ValueError as error:
        raise ValueError("Resource path is outside the OKF knowledge directory.") from error
    if not path.name.endswith(".okf.json"):
        raise ValueError("Resource path is outside the OKF knowledge directory.")
    return {
        "contents": [
            {
                "uri": uri,
                "mimeType": "application/json",
                "text": path.read_text(encoding="utf-8"),
            }
        ]
    }


def read_okf_entry(uri: str) -> dict[str, Any]:
    entry_id = unquote(uri.removeprefix("okf://entry/"))
    for chunk in auralyze.knowledge_chunks():
        if str(chunk.get("id")) == entry_id:
            return resource_text(uri, chunk)
    raise ValueError(f"Unknown OKF entry: {entry_id}")


def resource_text(uri: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "contents": [
            {
                "uri": uri,
                "mimeType": "application/json",
                "text": json.dumps(payload, indent=2),
            }
        ]
    }


def clamp_int(value: object, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = maximum
    return max(minimum, min(maximum, parsed))


def result_response(request_id: object, result: dict[str, Any]) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def error_response(
    request_id: object,
    code: int,
    message: str,
    data: object | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": "2.0", "id": request_id, "error": error}


def write_message(message: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
