#!/usr/bin/env python3
"""Exercise real localhost inference, Swift compilation, JSON, and a file tool."""

import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


ENDPOINT = "http://127.0.0.1:11434"
MODEL = "qwen3-coder:30b"
THINKING_OPTION = None
class RejectRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), RejectRedirects())


def request(path, body=None, timeout=600):
    payload = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        ENDPOINT + path, payload,
        headers={"Content-Type": "application/json"},
    )
    with OPENER.open(req, timeout=timeout) as response:
        return json.load(response)


def pull():
    req = urllib.request.Request(
        ENDPOINT + "/api/pull",
        json.dumps({"model": MODEL}).encode(),
        headers={"Content-Type": "application/json"},
    )
    prior = None
    with OPENER.open(req, timeout=600) as response:
        for line in response:
            item = json.loads(line)
            if "error" in item:
                raise RuntimeError(item["error"])
            total = item.get("total", 0)
            fraction = item.get("completed", 0) / total if total else 0
            marker = (item.get("status", ""), int(fraction * 20))
            if marker != prior:
                print(json.dumps({
                    "status": item.get("status"),
                    "percent": round(fraction * 100),
                    "GB": round(item.get("completed", 0) / 1e9, 2),
                }), flush=True)
                prior = marker


def chat(messages, **kwargs):
    return request("/api/chat", {
        "model": MODEL,
        "messages": messages,
        "stream": False,
        "options": {"num_ctx": 32768, "temperature": 0, "num_predict": 2048},
        **({"think": THINKING_OPTION} if THINKING_OPTION is not None else {}),
        **kwargs,
    })


def benchmark(output):
    global THINKING_OPTION
    started = time.monotonic()
    metadata = request("/api/show", {"model": MODEL})
    if metadata.get("remote_model") or metadata.get("remote_host"):
        raise RuntimeError("This verification requires a downloaded local model.")
    thinking_values = (metadata.get("thinking") or {}).get("values", [])
    THINKING_OPTION = False if any(value is False for value in thinking_values) else None
    result = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "endpoint": ENDPOINT,
        "version": request("/api/version"),
        "model": next(m for m in request("/api/tags")["models"] if m["name"] == MODEL),
        "context_tokens": 32768,
        "capabilities": metadata.get("capabilities", []),
        "thinking_option": THINKING_OPTION,
    }
    with tempfile.TemporaryDirectory(prefix="vyron-local-proof-") as temporary:
        folder = Path(temporary)
        response = chat([{"role": "user", "content": (
            "Return only compilable Swift source, no markdown or explanation. "
            "Define func sum(_ values: [Int]) -> Int using reduce. "
            "At top level print sum([1, 2, 3, 4]). Use standard library only."
        )}])
        source = response["message"]["content"].strip()
        if source.startswith("```"):
            source = re.sub(r"^```[^\n]*\n|\n```$", "", source)
        swift_file = folder / "main.swift"
        swift_file.write_text(source + "\n")
        compiled = subprocess.run(
            ["/usr/bin/xcrun", "swiftc", str(swift_file), "-o", str(folder / "proof")],
            capture_output=True, text=True, timeout=120,
        )
        if compiled.returncode:
            raise RuntimeError("Generated Swift failed to compile: " + compiled.stderr)
        executed = subprocess.run([str(folder / "proof")], capture_output=True, text=True, timeout=10)
        assert executed.returncode == 0 and executed.stdout.strip() == "10", executed.stdout
        result["swift"] = {
            "passed": True, "source": source,
            "compiler_exit": compiled.returncode, "compiler_stderr": compiled.stderr,
            "stdout": executed.stdout,
            "generated_tokens": response.get("eval_count"),
            "load_seconds": round(response.get("load_duration", 0) / 1e9, 2),
            "tokens_per_second": round(response.get("eval_count", 0) / max(response.get("eval_duration", 1) / 1e9, 1e-9), 2),
        }
        print("PASS: generated Swift compiled and printed 10", flush=True)

        try:
            structured = chat([{"role": "user", "content": "Return JSON with language Swift and sum of 1, 2, 3, 4."}], format={
                "type": "object", "properties": {"language": {"type": "string"}, "sum": {"type": "integer"}},
                "required": ["language", "sum"], "additionalProperties": False,
            })
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            if error.code != 501 or "structured output is unavailable" not in detail:
                raise
            result["structured_output"] = {"supported": False, "passed": False, "http_status": 501, "detail": detail}
            print("UNSUPPORTED: this runtime does not provide constrained JSON-schema output", flush=True)
        else:
            value = json.loads(structured["message"]["content"])
            assert value == {"language": "Swift", "sum": 10}, value
            result["structured_output"] = {"supported": True, "passed": True, "value": value}
            print("PASS: structured JSON matches expected values", flush=True)

        fixture = folder / "Example.swift"
        fixture.write_text('let projectName = "VyronProof742"\n')
        messages = [{"role": "user", "content": "Use read_file to read Example.swift and tell me its projectName constant. Do not guess."}]
        tools = [{"type": "function", "function": {
            "name": "read_file", "description": "Read a named file from the selected project.",
            "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]},
        }}]
        tool_response = chat(messages, tools=tools)
        calls = tool_response["message"].get("tool_calls", [])
        assert len(calls) == 1, tool_response
        call = calls[0]["function"]
        assert call["name"] == "read_file" and call["arguments"]["path"] == "Example.swift", call
        messages.append(tool_response["message"])
        messages.append({"role": "tool", "tool_name": "read_file", "content": fixture.read_text()})
        final_response = chat(messages)
        answer = final_response["message"]["content"]
        assert "VyronProof742" in answer, answer
        result["tool_call"] = {"passed": True, "call": call, "actual_file_read": True, "answer": answer}
        print("PASS: real tool call read a fixture and used the result", flush=True)

    result["running_models"] = request("/api/ps")
    result["elapsed_seconds"] = round(time.monotonic() - started, 2)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n")
    print("Results: " + str(output), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--output", type=Path, default=Path(".build/verification/local-inference-proof.json"))
    args = parser.parse_args()
    MODEL = args.model
    if args.download:
        pull()
    else:
        benchmark(args.output)
