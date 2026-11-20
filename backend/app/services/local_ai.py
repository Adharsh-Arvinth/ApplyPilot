"""Free AI that runs anywhere ApplyPilot runs — no Gemini key needed.

Order of preference (Settings › AI answers › mode):
  auto   – Gemini (your key) first; when it is missing, over quota or down → the free local model → free cloud model
  local  – only the free local model (private: nothing leaves this computer) → free cloud model
  gemini – only Gemini

Local model: an open Qwen3.5 model served by Ollama (https://ollama.com) on the computer that runs ApplyPilot.
The size is chosen for the hardware, so any PC (or a small cloud server) can run one; phones talk to that server.
Free cloud model: any OpenAI-compatible endpoint (e.g. Groq or OpenRouter free models) with a free key, for
computers that can't run even the smallest local model.
"""
import json
import logging
import re
import shutil
import subprocess
import threading
import time
from typing import Any, Dict, List, Optional

import httpx

logger = logging.getLogger("applypilot.local_ai")

DEFAULT_URL = "http://127.0.0.1:11434"
# (tag, download size, min GPU memory GB, min RAM GB) — biggest first; the first one the hardware can hold wins
MODELS = [
    ("qwen3.5:9b", "6.6 GB", 8, 24),
    ("qwen3.5:4b", "4.0 GB", 4, 12),
    ("qwen3.5:2b", "2.7 GB", 0, 6),
    ("qwen3.5:0.8b", "1.3 GB", 0, 0),
]
DEFAULTS: Dict[str, Any] = {"mode": "auto", "model": "auto", "url": DEFAULT_URL,
                            "cloud": {"url": "", "model": "", "key_enc": ""}}
THINK = re.compile(r"<think>.*?</think>", re.S)


class LocalAI:
    _status_cache: Dict[str, Any] = {}
    _status_at: float = 0.0
    _hw: Optional[Dict[str, Any]] = None
    pull_state: Dict[str, Any] = {"model": None, "status": "idle", "done": 0, "total": 0, "error": ""}

    # ── settings ──
    @staticmethod
    def config() -> Dict[str, Any]:
        from backend.app.core.app_settings import get_setting
        from backend.app.core.database import SessionLocal
        db = SessionLocal()
        try:
            cfg = {**DEFAULTS, **(get_setting(db, "local_ai", {}) or {})}
            cfg["cloud"] = {**DEFAULTS["cloud"], **(cfg.get("cloud") or {})}
            return cfg
        finally:
            db.close()

    @staticmethod
    def save_config(patch: Dict[str, Any]) -> Dict[str, Any]:
        from backend.app.core.app_settings import set_setting
        from backend.app.core.database import SessionLocal
        from backend.app.core.security import encrypt_value
        cfg = LocalAI.config()
        if patch.get("mode") in ("auto", "local", "gemini"):
            cfg["mode"] = patch["mode"]
        if isinstance(patch.get("model"), str) and (patch["model"] == "auto" or re.fullmatch(r"[\w.:/-]{2,80}", patch["model"])):
            cfg["model"] = patch["model"]
        if isinstance(patch.get("url"), str) and patch["url"].startswith(("http://", "https://")):
            cfg["url"] = patch["url"].rstrip("/")
        cloud = patch.get("cloud")
        if isinstance(cloud, dict):
            if "url" in cloud:
                cfg["cloud"]["url"] = str(cloud["url"]).strip().rstrip("/")
            if "model" in cloud:
                cfg["cloud"]["model"] = str(cloud["model"]).strip()
            if cloud.get("key"):
                cfg["cloud"]["key_enc"] = encrypt_value(str(cloud["key"]).strip())
            if cloud.get("clear_key"):
                cfg["cloud"]["key_enc"] = ""
        db = SessionLocal()
        try:
            set_setting(db, "local_ai", cfg)
        finally:
            db.close()
        LocalAI._status_at = 0
        return cfg

    # ── hardware → model size ──
    @classmethod
    def hardware(cls) -> Dict[str, Any]:
        if cls._hw is None:
            ram = 0.0
            try:
                import psutil
                ram = psutil.virtual_memory().total / 1024 ** 3
            except Exception:
                pass
            vram, gpu = 0.0, ""
            if shutil.which("nvidia-smi"):
                try:
                    out = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
                                         capture_output=True, text=True, timeout=5).stdout.strip().splitlines()
                    if out:
                        name, mem = out[0].rsplit(",", 1)
                        gpu, vram = name.strip(), float(mem) / 1024
                except Exception:
                    pass
            cls._hw = {"ram_gb": round(ram, 1), "gpu": gpu, "gpu_gb": round(vram, 1)}
        return cls._hw

    @classmethod
    def recommended(cls) -> str:
        hw = cls.hardware()
        for tag, _size, gpu_min, ram_min in MODELS:
            if (gpu_min and hw["gpu_gb"] >= gpu_min) or (ram_min and hw["ram_gb"] >= ram_min) or (not gpu_min and not ram_min):
                return tag
        return MODELS[-1][0]

    @classmethod
    def model(cls, cfg: Optional[Dict[str, Any]] = None) -> str:
        cfg = cfg or cls.config()
        return cls.recommended() if cfg.get("model") in (None, "", "auto") else cfg["model"]

    # ── is it there? (cached for 20 s; never blocks long) ──
    @classmethod
    def status(cls, fresh: bool = False) -> Dict[str, Any]:
        if not fresh and time.time() - cls._status_at < 20 and cls._status_cache:
            return {**cls._status_cache, "pull": dict(cls.pull_state)}
        cfg = cls.config()
        installed, models = False, []
        try:
            r = httpx.get(f"{cfg['url']}/api/tags", timeout=1.5)
            installed = r.status_code == 200
            models = [m.get("name", "") for m in r.json().get("models", [])] if installed else []
        except Exception:
            pass
        chosen = cls.model(cfg)
        ready = installed and any(m == chosen or m.split(":latest")[0] == chosen for m in models)
        cloud = cfg["cloud"]
        st = {
            "mode": cfg["mode"], "url": cfg["url"], "installed": installed, "models": models,
            "model": chosen, "model_setting": cfg["model"], "recommended": cls.recommended(), "ready": ready,
            "hardware": cls.hardware(), "choices": [{"tag": t, "size": s} for t, s, _g, _r in MODELS],
            "cloud": {"url": cloud["url"], "model": cloud["model"], "has_key": bool(cloud["key_enc"]),
                      "ready": bool(cloud["url"] and cloud["model"] and cloud["key_enc"])},
        }
        cls._status_cache, cls._status_at = st, time.time()
        return {**st, "pull": dict(cls.pull_state)}

    @classmethod
    def available(cls) -> bool:
        st = cls.status()
        return st["mode"] != "gemini" and (st["ready"] or st["cloud"]["ready"])

    # ── talk to it ──
    @classmethod
    def chat(cls, prompt: str, system: Optional[str] = None, json_mode: bool = False, timeout: float = 45.0) -> Optional[str]:
        """Free model answer, or None. Local first, then the free cloud endpoint."""
        st = cls.status()
        if st["mode"] == "gemini":
            return None
        messages = ([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": prompt}]
        if st["ready"]:
            try:
                body: Dict[str, Any] = {"model": st["model"], "messages": messages, "stream": False, "think": False,
                                        "keep_alive": "30m",
                                        "options": {"temperature": 0.2 if json_mode else 0.5, "num_ctx": 8192}}
                if json_mode:
                    body["format"] = "json"
                r = httpx.post(f"{st['url']}/api/chat", json=body, timeout=timeout)
                r.raise_for_status()
                text = THINK.sub("", (r.json().get("message") or {}).get("content", "")).strip()
                if text:
                    return text
            except Exception as e:
                logger.warning(f"Local model {st['model']} failed: {e}")
        cloud = cls.config()["cloud"]
        if cloud["url"] and cloud["model"] and cloud["key_enc"]:
            try:
                from backend.app.core.security import decrypt_value
                body = {"model": cloud["model"], "messages": messages, "temperature": 0.2 if json_mode else 0.5}
                if json_mode:
                    body["response_format"] = {"type": "json_object"}
                r = httpx.post(f"{cloud['url']}/chat/completions", json=body, timeout=timeout,
                               headers={"Authorization": f"Bearer {decrypt_value(cloud['key_enc'])}"})
                r.raise_for_status()
                text = THINK.sub("", r.json()["choices"][0]["message"]["content"] or "").strip()
                if text:
                    return text
            except Exception as e:
                logger.warning(f"Free cloud model failed: {e}")
        return None

    # ── download a model (runs in the background; the app shows progress) ──
    @classmethod
    def start_pull(cls, model: Optional[str] = None) -> Dict[str, Any]:
        st = cls.status(fresh=True)
        if not st["installed"]:
            raise RuntimeError("Ollama isn't running on this computer yet. Install it from ollama.com, then try again.")
        if cls.pull_state["status"] == "pulling":
            return dict(cls.pull_state)
        tag = model or st["model"]
        cls.pull_state.update({"model": tag, "status": "pulling", "done": 0, "total": 0, "error": ""})

        def run():
            try:
                with httpx.stream("POST", f"{st['url']}/api/pull", json={"model": tag, "stream": True}, timeout=None) as r:
                    for line in r.iter_lines():
                        if not line:
                            continue
                        ev = json.loads(line)
                        if ev.get("error"):
                            raise RuntimeError(ev["error"])
                        if ev.get("total"):
                            cls.pull_state.update({"total": ev["total"], "done": ev.get("completed", 0)})
                        if ev.get("status") == "success":
                            cls.pull_state["status"] = "done"
                if cls.pull_state["status"] != "done":
                    cls.pull_state["status"] = "done"
            except Exception as e:
                cls.pull_state.update({"status": "error", "error": str(e)[:200]})
            finally:
                cls._status_at = 0

        threading.Thread(target=run, daemon=True, name="ollama-pull").start()
        return dict(cls.pull_state)

    @classmethod
    def list_models(cls) -> List[str]:
        return cls.status(fresh=True)["models"]
