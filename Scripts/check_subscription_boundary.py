#!/usr/bin/env python3
"""Regression guard for the server-authoritative subscription boundary."""

from __future__ import annotations

import ast
from pathlib import Path


SOURCE = Path(__file__).parents[1] / "backend" / "app_store.py"


def main() -> None:
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"), filename=str(SOURCE))
    function = next(
        (
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "verify_pro_subscription"
        ),
        None,
    )
    if function is None:
        raise SystemExit("verify_pro_subscription is missing")

    source = ast.get_source_segment(SOURCE.read_text(encoding="utf-8"), function) or ""
    required = (
        "if signed_transaction_info:",
        "Client-supplied signed transaction data is not accepted.",
        "signed_payload = fetch_signed_transaction_info(",
    )
    missing = [fragment for fragment in required if fragment not in source]
    if missing:
        raise SystemExit(
            "subscription verification still trusts client proof; missing: "
            + ", ".join(missing)
        )
    if "signed_payload = signed_transaction_info" in source:
        raise SystemExit("client-provided JWS is still selected as trusted proof")

    print("Subscription verification requires an Apple server lookup.")


if __name__ == "__main__":
    main()
