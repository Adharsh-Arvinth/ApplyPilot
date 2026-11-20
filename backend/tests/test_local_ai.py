"""Free AI fallback: talks to an Ollama-compatible server, sizes the model to the hardware, and answers
whenever Gemini can't. Uses a tiny fake Ollama server, so no model download is needed."""
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
from fastapi.testclient import TestClient

from backend.app.core.config import settings
from backend.app.main import app
from backend.app.services.gemini_service import GeminiService
from backend.app.services.local_ai import LocalAI, MODELS

client = TestClient(app)
AUTH = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}
SEEN = []


class FakeOllama(BaseHTTPRequestHandler):
    def _send(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/tags":
            self._send({"models": [{"name": "qwen3.5:2b"}]})

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        SEEN.append(req)
        if self.path == "/api/chat":
            content = '{"answer": "ok"}' if req.get("format") == "json" else "<think>hmm</think>Hello from the free model"
            self._send({"message": {"role": "assistant", "content": content}})

    def log_message(self, *a):
        pass


@pytest.fixture()
def fake_ollama(monkeypatch):
    srv = HTTPServer(("127.0.0.1", 0), FakeOllama)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    saved = LocalAI.config()
    LocalAI.save_config({"url": f"http://127.0.0.1:{srv.server_port}", "model": "qwen3.5:2b", "mode": "auto"})
    monkeypatch.setattr(GeminiService, "get_client", classmethod(lambda cls: None))  # no Gemini at all
    SEEN.clear()
    yield srv
    LocalAI.save_config({"url": saved["url"], "model": saved["model"], "mode": saved["mode"]})
    srv.shutdown()


def test_model_size_follows_the_hardware(monkeypatch):
    for hw, want in [({"ram_gb": 32, "gpu": "", "gpu_gb": 0}, "qwen3.5:9b"), ({"ram_gb": 14, "gpu": "x", "gpu_gb": 4}, "qwen3.5:4b"),
                     ({"ram_gb": 8, "gpu": "", "gpu_gb": 0}, "qwen3.5:2b"), ({"ram_gb": 4, "gpu": "", "gpu_gb": 0}, "qwen3.5:0.8b")]:
        monkeypatch.setattr(LocalAI, "_hw", hw)
        assert LocalAI.recommended() == want, hw
    assert [m[0] for m in MODELS][-1] == "qwen3.5:0.8b"  # something always fits


def test_free_model_answers_when_gemini_is_missing(fake_ollama):
    st = LocalAI.status(fresh=True)
    assert st["installed"] and st["ready"] and st["model"] == "qwen3.5:2b"
    assert GeminiService.available()
    assert GeminiService._call_model("Say hello", "be brief") == "Hello from the free model"  # <think> removed
    assert GeminiService._call_model("json please", None, json_mode=True) == '{"answer": "ok"}'
    assert SEEN[-1]["format"] == "json" and SEEN[-1]["think"] is False and SEEN[-1]["model"] == "qwen3.5:2b"


def test_gemini_only_mode_never_uses_the_free_model(fake_ollama):
    LocalAI.save_config({"mode": "gemini"})
    assert GeminiService._call_model("Say hello") is None and not SEEN


def test_free_ai_settings_api(fake_ollama):
    st = client.get("/api/v1/ai/local", headers=AUTH).json()
    assert st["installed"] and {c["tag"] for c in st["choices"]} >= {"qwen3.5:4b", "qwen3.5:0.8b"}
    st = client.put("/api/v1/ai/local", headers=AUTH, json={"mode": "local", "cloud": {"url": "https://example.com/v1", "model": "m", "key": "secret-key-123"}}).json()
    assert st["mode"] == "local" and st["cloud"]["has_key"] and "secret-key-123" not in json.dumps(st)
    client.put("/api/v1/ai/local", headers=AUTH, json={"cloud": {"url": "", "model": "", "clear_key": True}})
    client.cookies.clear()  # earlier calls left the (valid) sign-in cookie
    assert client.get("/api/v1/ai/local").status_code == 401


def test_phone_gets_a_compact_grounded_prompt():
    from backend.app.services.gemini_service import CANDIDATE_FACTS
    res = client.post("/api/v1/ai/chat-prompt", headers=AUTH, json={"message": "What needs me today?", "history": [{"role": "user", "content": "hi"}], "view": "home"})
    body = res.json()
    assert res.status_code == 200 and set(body) == {"system", "prompt"}
    assert "never invent" in body["system"] and CANDIDATE_FACTS.splitlines()[0] in body["system"]
    assert "LIVE STATE" in body["prompt"] and body["prompt"].rstrip().endswith("User: What needs me today?")
    assert len(body["system"]) + len(body["prompt"]) < 6000  # small enough for a small on-device model
