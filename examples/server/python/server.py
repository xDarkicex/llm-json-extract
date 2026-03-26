#!/usr/bin/env python3
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

HOST = "0.0.0.0"
PORT = 8082
EXTRACTOR_PATH = os.environ.get("EXTRACTOR_PATH", "../../../llm-json-extract.pl")
EXTRACTOR_ARGS = [
    "perl",
    EXTRACTOR_PATH,
    "--meta",
    "--fallback-empty",
    "--timeout", "2",
    "--max-size", "10M",
    "--max-candidate", "2M",
    "--max-repair-size", "1M",
]


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True})
            return
        self._json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/extract":
            self._json(404, {"error": "not_found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length)
            payload = json.loads(raw_body.decode("utf-8"))
        except Exception:
            self._json(400, {"error": "invalid_json_body"})
            return

        raw = payload.get("raw", "")
        if not isinstance(raw, str) or not raw.strip():
            self._json(400, {"error": "raw_is_required"})
            return

        try:
            proc = subprocess.run(
                EXTRACTOR_ARGS,
                input=raw,
                text=True,
                capture_output=True,
                timeout=5,
            )
        except Exception as exc:
            self._json(502, {"error": "extract_exec_failed", "details": str(exc)})
            return

        stdout = proc.stdout or ""
        stderr = proc.stderr or ""

        if proc.returncode != 0:
            self._json(502, {
                "error": "extract_exec_failed",
                "exit_code": proc.returncode,
                "stderr": stderr,
                "extractor": stdout.strip(),
            })
            return

        try:
            json.loads(stdout)
        except Exception:
            self._json(502, {
                "error": "extractor_returned_non_json",
                "extractor": stdout.strip(),
                "stderr": stderr,
                "exit_code": proc.returncode,
            })
            return

        body = stdout.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), Handler)
    print(f"python example listening on {HOST}:{PORT}")
    server.serve_forever()
