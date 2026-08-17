#!/usr/bin/env python3
import ast
from pathlib import Path

source_path = Path(__file__).parents[1] / "backend/main.py"
source = source_path.read_text(encoding="utf-8")
tree = ast.parse(source)
email_send = next(
    node for node in tree.body
    if isinstance(node, ast.AsyncFunctionDef) and node.name == "email_send"
)
email_send_source = ast.get_source_segment(source, email_send) or ""
if "require_trusted_email_user" not in email_send_source:
    raise SystemExit("email_send does not require a trusted identity")
if 'token.get("source") not in {"apple", "platform"}' not in source:
    raise SystemExit("trusted email guard does not reject legacy device tokens")
print("Email send requires a trusted Apple or platform identity.")
