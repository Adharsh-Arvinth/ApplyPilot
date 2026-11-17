import os
from pathlib import Path
import pypdf

targets = [
    "drowsiness",
    "speculative token pruning",
    "Expected May 2027",
    "Immediate / 15 Days",
    "10pt"
]

# Text files to search
text_exts = {".py", ".md", ".json", ".dart", ".yaml", ".yml", ".txt", ".html", ".css", ".js"}
ignore_dirs = {".git", ".pytest_cache", "__pycache__", "build", ".dart_tool", "web", "windows", "ios", "android", "linux", "macos"}

text_matches = []
for p in Path(".").rglob("*"):
    if not p.is_file():
        continue
    if any(ig in p.parts for ig in ignore_dirs):
        continue
    if p.suffix.lower() in text_exts:
        try:
            content = p.read_text(encoding="utf-8", errors="ignore")
            for t in targets:
                if t.lower() in content.lower():
                    # Ignore the test file where we intentionally test rejection of fake claims
                    if p.name in ["test_facts_grounding.py", "test_gemini_auto_answer.py", "search_stale_facts.py"]:
                        continue
                    text_matches.append((str(p), t))
        except Exception:
            pass

print("=== TEXT MATCHES ===")
for p, t in sorted(set(text_matches)):
    print(f"File: {p} -> Found: {t}")

# PDF files search
pdf_matches = []
for p in Path(".").rglob("*.pdf"):
    if any(ig in p.parts for ig in ignore_dirs):
        continue
    try:
        reader = pypdf.PdfReader(str(p))
        text = ""
        for page in reader.pages:
            text += page.extract_text() or ""
        for t in targets + ["Associate"]:
            if t.lower() in text.lower():
                pdf_matches.append((str(p), t))
    except Exception as e:
        pass

print("\n=== PDF MATCHES ===")
for p, t in sorted(set(pdf_matches)):
    print(f"PDF: {p} -> Found: {t}")
