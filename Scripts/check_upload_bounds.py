#!/usr/bin/env python3
import ast
from pathlib import Path

source_path = Path(__file__).parents[1] / "backend/main.py"
source = source_path.read_text(encoding="utf-8")
tree = ast.parse(source)
if "async def read_limited_upload(" not in source:
    raise SystemExit("limited upload reader is missing")
for name in ("transcribe_openai", "transcribe_elevenlabs", "transcribe_luxasr", "email_send"):
    function = next(
        node for node in tree.body
        if isinstance(node, ast.AsyncFunctionDef) and node.name == name
    )
    function_source = ast.get_source_segment(source, function) or ""
    if "read_limited_upload" not in function_source:
        raise SystemExit(f"{name} still performs an unbounded upload read")
print("All upload endpoints use read_limited_upload.")
